-- Run after casino-migration.sql. Virtual currency only.
create table if not exists public.hub_game_state(member_id uuid primary key references auth.users(id) on delete cascade, die int not null default 4, player int[], dealer int[], wager bigint not null default 0);
alter table public.hub_game_state enable row level security;
revoke all on public.hub_game_state from public,anon,authenticated;
create or replace function public.hub_card_total(cards int[]) returns int language plpgsql immutable set search_path='' as $$ declare t int:=0; a int:=0; c int; begin foreach c in array cards loop t:=t+least(c,10); if c=1 then a:=a+1; end if; end loop; if a>0 and t+10<=21 then t:=t+10; end if; return t; end $$;
create or replace function public.hub_game(game text, choice text, stake bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare b bigint; s public.hub_game_state%rowtype; p bigint:=0; cost bigint:=0; n int; olddie int; outcome text; msg text:=''; win boolean; pt int; dt int; settled boolean:=false; red int[]:=array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36];
begin
if not public.hub_is_member() then raise exception 'Members only'; end if;
if game is null or game not in ('dice','coin','roulette','blackjack') or choice is null then raise exception 'Invalid game'; end if;
perform public.hub_wallet(); select balance into b from public.hub_wallets where member_id=auth.uid() for update;
insert into public.hub_game_state(member_id,die) values(auth.uid(),1+floor(random()*6)::int) on conflict do nothing;
select * into s from public.hub_game_state where member_id=auth.uid() for update;
if choice<>'state' then
 if game<>'blackjack' or choice='deal' then if stake is null or stake<1 or stake>1000000 or stake>b then raise exception 'Invalid bet or insufficient balance'; end if; cost:=stake; end if;
 if game='dice' then
 olddie:=s.die; if choice not in ('higher','lower') or (choice='higher' and olddie=6) or (choice='lower' and olddie=1) then raise exception 'Invalid prediction'; end if;
 n:=1+floor(random()*6)::int; s.die:=n; if n=olddie then p:=stake; elsif (choice='higher' and n>olddie) or (choice='lower' and n<olddie) then p:=floor(stake*4.85/(case when choice='higher' then 6-olddie else olddie-1 end)); end if; outcome:=n::text;
 elsif game='coin' then if choice not in ('heads','tails') then raise exception 'Invalid side'; end if; outcome:=case when random()<.5 then 'heads' else 'tails' end; if outcome=choice then p:=stake*2; end if;
 elsif game='roulette' then
 n:=floor(random()*37)::int; outcome:=n::text;
 if choice ~ '^(0|[1-9]|[12][0-9]|3[0-6])$' then if n=choice::int then p:=stake*36; end if;
 elsif choice in ('red','black','odd','even','low','high','first','second','third') then
 win:=n<>0 and (case choice when 'red' then n=any(red) when 'black' then not(n=any(red)) when 'odd' then n%2=1 when 'even' then n%2=0 when 'low' then n<=18 when 'high' then n>=19 when 'first' then n<=12 when 'second' then n between 13 and 24 when 'third' then n>=25 end); if win then p:=stake*(case when choice in ('first','second','third') then 3 else 2 end); end if;
 else raise exception 'Invalid roulette bet'; end if;
 else
 if choice='deal' then if s.wager>0 then raise exception 'Finish current hand'; end if; s.wager:=stake; s.player:=array[1+floor(random()*13)::int,1+floor(random()*13)::int]; s.dealer:=array[1+floor(random()*13)::int,1+floor(random()*13)::int]; pt:=public.hub_card_total(s.player); dt:=public.hub_card_total(s.dealer); if pt=21 or dt=21 then settled:=true; if pt=dt then p:=s.wager; elsif pt=21 then p:=floor(s.wager*2.5); end if; end if;
 elsif choice in ('hit','stand','double') then if s.wager=0 then raise exception 'No active hand'; end if; if choice='double' then if cardinality(s.player)<>2 or b<s.wager then raise exception 'Cannot double'; end if; cost:=s.wager; s.wager:=s.wager*2; end if; if choice<>'stand' then s.player:=array_append(s.player,1+floor(random()*13)::int); end if; pt:=public.hub_card_total(s.player); if pt>21 then settled:=true; elsif choice<>'hit' or pt=21 then while public.hub_card_total(s.dealer)<17 loop s.dealer:=array_append(s.dealer,1+floor(random()*13)::int); end loop; dt:=public.hub_card_total(s.dealer); settled:=true; if dt>21 or pt>dt then p:=s.wager*2; elsif pt=dt then p:=s.wager; end if; end if;
 else raise exception 'Invalid blackjack action'; end if;
 if settled then msg:='Hand settled. Payout: $'||p; s.wager:=0; else msg:='Hand in progress'; end if;
 end if;
 b:=b-cost+p; update public.hub_wallets set balance=b where member_id=auth.uid(); update public.hub_game_state set die=s.die,player=s.player,dealer=s.dealer,wager=s.wager where member_id=auth.uid();
 insert into public.hub_casino_log(member_id,actor,kind,bet,payout,balance) values(auth.uid(),auth.uid(),game||':'||choice,cost,p,b);
 if game<>'blackjack' then msg:='Payout: $'||p; end if;
end if;
return jsonb_build_object('balance',b,'die',s.die,'outcome',outcome,'message',msg,'active',s.wager>0,'player',s.player,'dealer',case when s.wager>0 then s.dealer[1:1] else s.dealer end);
end $$;
revoke execute on function public.hub_game(text,text,bigint),public.hub_card_total(int[]) from public,anon;
grant execute on function public.hub_game(text,text,bigint) to authenticated;
drop function if exists public.hub_rascal_spin(bigint);
create or replace function public.hub_reset_wallet(target uuid) returns void language plpgsql security definer set search_path='' as $$ begin if not public.hub_is_admin() then raise exception 'Admin only'; end if; if not exists(select 1 from public.hub_members where id=target) and not exists(select 1 from public.hub_admins where id=target) then raise exception 'Unknown member'; end if; insert into public.hub_wallets(member_id,balance) values(target,500000) on conflict(member_id) do update set balance=500000; delete from public.hub_game_state where member_id=target; insert into public.hub_casino_log(member_id,actor,kind,balance) values(target,auth.uid(),'reset',500000); end $$;
