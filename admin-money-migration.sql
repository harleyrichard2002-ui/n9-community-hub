-- Run after casino-migration.sql and games-migration.sql.
begin;
create or replace function public.hub_add_money(target uuid, amount bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare b bigint;
begin
  if auth.uid() is null or not public.hub_is_admin() then raise exception 'Admin only'; end if;
  if amount is null or amount < 1 or amount > 1000000000 then raise exception 'Invalid amount'; end if;
  if target is null or not (exists(select 1 from public.hub_members where id=target) or exists(select 1 from public.hub_admins where id=target)) then raise exception 'Unknown member'; end if;
  insert into public.hub_wallets(member_id) values(target) on conflict do nothing;
  update public.hub_wallets set balance=balance+amount where member_id=target returning balance into b;
  insert into public.hub_casino_log(member_id,actor,kind,payout,balance) values(target,auth.uid(),'admin_topup',amount,b);
  return b;
end $$;
revoke all on function public.hub_add_money(uuid,bigint) from public,anon;
grant execute on function public.hub_add_money(uuid,bigint) to authenticated;
commit;
