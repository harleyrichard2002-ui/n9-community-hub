-- Requires V3 casino-migration.sql first. Shared virtual wallet.
create or replace function public.hub_rascal_spin(stake bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare b bigint; p bigint:=0; g text[][]; frames jsonb:='[]'; syms text[]:=array['J','Q','K','A','bread','cheese','beer','trap']; weights int[]:=array[14,14,13,13,9,7,6,4]; vals numeric[]:=array[.046,.0552,.069,.092,.138,.23,.368,.69]; c int; r int; k int; j int; n int; x int; t int; roundno int; gain numeric; hits text[]; keep text[];
begin
if not public.hub_is_member() then raise exception 'Members only'; end if;
if stake is null or not(stake=any(array[100,500,1000,5000,10000,25000,50000,100000]::bigint[])) then raise exception 'Invalid bet'; end if;
perform public.hub_wallet(); select balance into b from public.hub_wallets where member_id=auth.uid() for update;
if b<stake then raise exception 'Insufficient balance'; end if;
g:=array_fill(null::text,array[6,5]);
for roundno in 1..30 loop
 for c in 1..6 loop for r in 1..5 loop
 if g[c][r] is null then x:=floor(random()*80); for j in 1..8 loop x:=x-weights[j]; if x<0 then g[c][r]:=syms[j]; exit; end if; end loop; end if;
 end loop; end loop;
 frames:=frames||jsonb_build_array(to_jsonb(g)); gain:=0; hits:=array[]::text[];
 for k in 1..8 loop n:=0; for c in 1..6 loop for r in 1..5 loop if g[c][r]=syms[k] then n:=n+1; end if; end loop; end loop;
 if n>=8 then t:=case when n>=15 then 15 when n>=12 then 5 when n>=10 then 2 else 1 end; gain:=gain+stake*vals[k]*t; hits:=array_append(hits,syms[k]); end if; end loop;
 p:=p+floor(gain); if gain=0 then exit; end if;
 for c in 1..6 loop keep:=array[]::text[]; for r in reverse 5..1 loop if not(g[c][r]=any(hits)) then keep:=array_append(keep,g[c][r]); end if; end loop; for r in 1..5 loop g[c][r]:=null; end loop; for r in 1..coalesce(array_length(keep,1),0) loop g[c][6-r]:=keep[r]; end loop; end loop;
end loop;
b:=b-stake+p; update public.hub_wallets set balance=b where member_id=auth.uid(); insert into public.hub_casino_log(member_id,actor,kind,bet,payout,balance) values(auth.uid(),auth.uid(),'rascal_spin',stake,p,b); return jsonb_build_object('balance',b,'payout',p,'frames',frames);
end $$;
revoke execute on function public.hub_rascal_spin(bigint) from public,anon;
grant execute on function public.hub_rascal_spin(bigint) to authenticated;
