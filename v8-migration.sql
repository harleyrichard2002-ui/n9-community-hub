begin;
create or replace function public.hub_spin(stake bigint) returns jsonb language plpgsql security definer set search_path='' as $$ declare b bigint; r integer[]:=array[]::integer[]; n integer; i integer; p bigint:=0; begin if not public.hub_is_member() then raise exception 'Members only'; end if; if stake is null or stake<1 then raise exception 'Invalid bet'; end if; perform public.hub_wallet(); select balance into b from public.hub_wallets where member_id=auth.uid() for update; if b<stake then raise exception 'Insufficient balance'; end if; for i in 1..3 loop n:=floor(random()*100); r:=array_append(r,case when n<30 then 0 when n<55 then 1 when n<75 then 2 when n<88 then 3 when n<97 then 4 else 5 end); end loop; if r[1]=r[2] and r[2]=r[3] then p:=stake*(array[4,6,10,20,50,500])[r[1]+1]; elsif r[1]=r[2] or r[1]=r[3] or r[2]=r[3] then p:=stake; end if; b:=b-stake+p; update public.hub_wallets set balance=b where member_id=auth.uid(); insert into public.hub_casino_log(member_id,actor,kind,bet,payout,reels,balance) values(auth.uid(),auth.uid(),'spin',stake,p,r,b); return jsonb_build_object('balance',b,'reels',r,'payout',p); end $$;
create or replace function public.hub_game(game text, choice text, stake bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare b bigint; s public.hub_game_state%rowtype; p bigint:=0; cost bigint:=0; n int; olddie int; outcome text; msg text:=''; win boolean; pt int; dt int; settled boolean:=false; red int[]:=array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36];
begin
if not public.hub_is_member() then raise exception 'Members only'; end if;
if game is null or game not in ('dice','coin','roulette','blackjack') or choice is null then raise exception 'Invalid game'; end if;
perform public.hub_wallet(); select balance into b from public.hub_wallets where member_id=auth.uid() for update;
insert into public.hub_game_state(member_id,die) values(auth.uid(),1+floor(random()*6)::int) on conflict do nothing;
select * into s from public.hub_game_state where member_id=auth.uid() for update;
if choice<>'state' then
 if game<>'blackjack' or choice='deal' then if stake is null or stake<1 or stake>b then raise exception 'Invalid bet or insufficient balance'; end if; cost:=stake; end if;
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
create table if not exists public.hub_extra_rounds(member_id uuid references auth.users(id) on delete cascade, game text, wager bigint not null, level int not null default 0, traps int[] not null default '{}', picked int[] not null default '{}', started timestamptz not null default clock_timestamp(), crash_at double precision, primary key(member_id,game));
alter table public.hub_extra_rounds enable row level security;
revoke all on public.hub_extra_rounds from public,anon,authenticated;
create or replace function public.hub_extra(game text, choice text, stake bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare b bigint; r public.hub_extra_rounds%rowtype; cost bigint:=0; payout bigint:=0; active boolean; n int; i int; m int; mult numeric:=1; elapsed double precision; msg text:=''; path int[]:='{}'; pocket int:=0; result int; done boolean:=false;
begin
if not public.hub_is_member() or auth.uid() is null then raise exception 'Members only'; end if;
if game is null or game not in ('crash','mines','plinko','tower','vault') or choice is null then raise exception 'Invalid game'; end if;
perform public.hub_wallet(); select balance into b from public.hub_wallets where member_id=auth.uid() for update;
select * into r from public.hub_extra_rounds x where x.member_id=auth.uid() and x.game=hub_extra.game; active:=found;
if active and game='crash' then elapsed:=extract(epoch from clock_timestamp()-r.started); if exp(least(elapsed,60)*0.12)>=r.crash_at then done:=true; msg:='Crashed at '||round(r.crash_at::numeric,2)||'×'; end if; end if;
if not done and choice<>'state' then
 if not active then
  if stake is null or stake<1 or stake>b then raise exception 'Invalid bet or insufficient balance'; end if;
  cost:=stake;
  if game='plinko' and choice='start' then for i in 1..8 loop n:=floor(random()*2)::int; path:=array_append(path,n); pocket:=pocket+n; end loop; mult:=(array[8,3,1.5,.7,.5,.7,1.5,3,8]::numeric[])[pocket+1]; payout:=floor(stake*mult); msg:='Pocket '||pocket||' · '||mult||'×';
  elsif game='vault' and choice ~ '^[0-5]$' then result:=floor(random()*6)::int; mult:=case when result=choice::int then 5 else 0 end; payout:=stake*mult; msg:='Winning vault: '||(result+1)||' · '||mult||'×';
  elsif game in ('mines','tower','crash') and (choice='start' or (game='mines' and choice ~ '^start:([1-9]|1[0-9]|2[0-4])$')) then
   r.member_id:=auth.uid(); r.game:=game; r.wager:=stake; r.level:=0; r.picked:='{}'; r.traps:='{}'; r.started:=clock_timestamp();
   if game='mines' then m:=case when choice='start' then 3 else split_part(choice,':',2)::int end; select array_agg(v) into r.traps from (select v from generate_series(0,24) v order by random() limit m) z;
   elsif game='tower' then for i in 1..8 loop r.traps:=array_append(r.traps,floor(random()*3)::int); end loop;
   else r.crash_at:=least(1000, greatest(1, .97/greatest(random(),.000001))); end if;
   insert into public.hub_extra_rounds values(r.*); active:=true; msg:='Round started';
  else raise exception 'Invalid action'; end if;
 else
  if choice='cash' then if game<>'crash' and r.level=0 then raise exception 'Reveal a safe tile first'; end if; done:=true;
  elsif game='mines' and choice ~ '^([0-9]|1[0-9]|2[0-4])$' then n:=choice::int; if n=any(r.picked) then raise exception 'Already revealed'; end if; if n=any(r.traps) then done:=true; msg:='Mine hit'; else r.picked:=array_append(r.picked,n); r.level:=r.level+1; if r.level=25-cardinality(r.traps) then done:=true; end if; end if;
  elsif game='tower' and choice ~ '^[0-2]$' then n:=choice::int; if n=r.traps[r.level+1] then done:=true; msg:='Trap hit'; else r.picked:=array_append(r.picked,n); r.level:=r.level+1; if r.level=8 then done:=true; end if; end if;
  else raise exception 'Invalid action'; end if;
  if done and msg='' then if game='crash' then mult:=floor(exp(least(elapsed,60)*.12)*100)/100; elsif game='tower' then mult:=.97*power(1.5::numeric,r.level); else mult:=.97; for i in 0..r.level-1 loop mult:=mult*(25-i)::numeric/(25-cardinality(r.traps)-i); end loop; end if; payout:=floor(r.wager*mult); msg:='Cashed out · '||round(mult,2)||'×'; end if;
 end if;
end if;
if active and not done then update public.hub_extra_rounds x set level=r.level,picked=r.picked where x.member_id=auth.uid() and x.game=hub_extra.game; end if;
if done then delete from public.hub_extra_rounds x where x.member_id=auth.uid() and x.game=hub_extra.game; active:=false; end if;
if cost>0 or payout>0 or done then b:=b-cost+payout; update public.hub_wallets set balance=b where member_id=auth.uid(); insert into public.hub_casino_log(member_id,actor,kind,bet,payout,balance) values(auth.uid(),auth.uid(),game||':'||choice,cost,payout,b); end if;
return jsonb_build_object('balance',b,'active',active,'level',coalesce(r.level,0),'picked',coalesce(r.picked,'{}'::int[]),'elapsed',case when active and game='crash' then extract(epoch from clock_timestamp()-r.started) else 0 end,'message',msg,'path',path,'pocket',pocket,'payout',payout);
end $$;
revoke all on function public.hub_extra(text,text,bigint) from public,anon;
grant execute on function public.hub_extra(text,text,bigint) to authenticated;
create or replace function public.hub_reset_wallet(target uuid) returns void language plpgsql security definer set search_path='' as $$ begin if not public.hub_is_admin() then raise exception 'Admin only'; end if; if not exists(select 1 from public.hub_members where id=target) and not exists(select 1 from public.hub_admins where id=target) then raise exception 'Unknown member'; end if; insert into public.hub_wallets(member_id,balance) values(target,500000) on conflict(member_id) do update set balance=500000; delete from public.hub_extra_rounds where member_id=target; delete from public.hub_game_state where member_id=target; insert into public.hub_casino_log(member_id,actor,kind,balance) values(target,auth.uid(),'reset',500000); end $$;

commit;
