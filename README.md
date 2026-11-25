# N9 Community Hub V6
Existing V5 users: run games-migration.sql in Supabase SQL Editor, then replace repository files with this package and redeploy. New installations run schema.sql, casino-migration.sql, then games-migration.sql. Keep existing Netlify environment variables and build command npm run build, publish dist. Remove old rascal files from repository. Virtual currency only. Blackjack uses independent card draws (infinite deck), dealer stands on 17, no splitting or insurance. Admin reset cancels active hands. Roulette uses single zero. Dice ties refund, coin pays 2x. Existing account creation remains. SQL and live deployment require testing in a staging project before production.

## V7 admin top-ups
Existing V6 installations: run only admin-money-migration.sql, then replace website files and redeploy. New installations: run this migration after the three earlier SQL files. Admin panel > Casino management > enter amount > Add money > confirm. Positive whole virtual dollars only, up to 1 billion per top-up. Uninitialized wallets start at 500,000 before the credit. Credits and audit records are atomic; active blackjack hands are unchanged. Test admin and non-admin access in staging before production.

## V8 upgrade from V7
Run v8-migration.sql in Supabase SQL Editor before deploying the updated files. Existing balances remain intact. Five new native games and a casino lobby are included. No fixed wager cap; database bigint and browser number precision impose technical limits. Crash uses server time; Plinko displays a generated path, not a physics simulation. Recent history is shown in the lobby. Optional play limits and lifetime statistics are not implemented. Test on a staging Supabase project before production.

## V9
Frontend-only update from V8. No new SQL required if V8 migration is installed. Auto drop runs one ball at a time and stops on navigation or insufficient funds.

## V10
Presentation update only; retain the V8 database migration. Roulette animation follows the returned pocket; blackjack totals use visible cards only during active hands. Vault reveal, slot motion and lobby cards are CSS-based.
