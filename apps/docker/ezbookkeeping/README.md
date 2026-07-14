
To-Do: Update "CHANGEME" password in /conf/ezbookkeeping.ini


Health
- Doctor Visit
- Dental Visit
- Prescription
- Mental Health
- Insurance
- Gym

IT
- IT Pro
- Domain
- Email
- Misc
- Subscription
- Apple Care

Financial
- Car loan
- Personal loan
- House loan
- Investments
- Balance Adjustment
- Card Payments
- Monthly Interest
- Dividend Payout
- Taxes

Shopping
- Clothing
- Merch
- Books
- Vinyl
- Misc
- Etsy

Entertainment
- Streaming Service
- Subscription
- Concert tickets
- Dates
- Misc
- Drugs

Travel
- Accomodation (hotels, airbnb)
- Food
- Travel tickets
- Gas

Food
- Restaurants
- Coffee
- DoorDash
- Delivery Subscription
- Alcohol
- Groceries
- MyProtein

Gaming
- Games
- Game subscription
- Mod subscription

Home
- Utilities
- Maintenance
- Furniture/Appliances
- Insurance

---

# ezBookkeeping

**URL:** https://bookkeeping.hughboi.cc
**Docs:** https://github.com/mayswind/ezbookkeeping

Personal finance tracker. Log income and expenses against the categories above, view trends, and keep track of where money goes.

## Stack

Two containers:

| Container | Role |
|---|---|
| `ezbookkeeping` | Main app + web UI |
| `ezbookkeeping-mysql` | MySQL 8.0 — transaction and account data |

## Network Layout

- `bookkeep` network: internal — app and MySQL only
- `proxy` network: app joins this for Traefik routing

## Volumes

| Mount | Purpose |
|---|---|
| `/etc/localtime:ro` | Timezone sync |
| `./storage` | App storage (attachments, exports) |
| `./log/ezbookkeeping` | Application logs |
| `./mysql-data` | MySQL data directory |

## Key Environment Variables

| Variable | Purpose |
|---|---|
| `EBK_DATABASE_PASSWD` | MySQL password for the ezbookkeeping user |
| `EBK_SECURITY_SECRET_KEY` | Secret key for session signing — generate with `openssl rand -hex 32` |
| `MYSQL_ROOT_PASSWORD` | MySQL root password |

## First Run

1. Fill in `.env`
2. `docker compose up -d`
3. Navigate to https://bookkeeping.hughboi.cc
4. Create an account on first visit
5. Set up accounts (checking, savings, credit cards) under **Accounts**
6. Add the transaction categories from the list above

## Upgrade Notes

- MySQL data is in `./mysql-data` (local to the compose directory). Back it up before upgrading.
- Check the [ezBookkeeping changelog](https://github.com/mayswind/ezbookkeeping/releases) for DB migration notes before major version bumps.

## Troubleshooting

**Can't connect to database on startup:**
- ezBookkeeping waits for MySQL healthy before starting (`depends_on: condition: service_healthy`)
- Check `docker logs ezbookkeeping-mysql` for startup errors

**Forgot password:**
- Reset via the MySQL CLI:
```sh
docker exec -it ezbookkeeping-mysql mysql -u ezbookkeeping -p ezbookkeeping
# Then: UPDATE users SET password = <new_hash> WHERE username = 'yourusername';
```
- Or recreate the account if data loss is acceptable

