# Návrh endpointu pro odesílání tras z hodinek Garmin

Pro správce API Žhavých míst. Aplikace Raysid pro hodinky Garmin (Connect IQ) zaznamenává body trasy (GPS, dávkový příkon z dozimetru Raysid, cps) a má je sama posílat na web přes telefon.

## Proč nestačí současné API

Trasy se dnes zakládají jen nahráním souboru přes `POST /api/1.0/all/managedata?tab=upload` (multipart/form-data). Hodinky Garmin posílají data výhradně funkcí `Communications.makeWebRequest`, která umí tělo jen jako JSON nebo `application/x-www-form-urlencoded`. Multipart a nahrání souboru Connect IQ nepodporuje. Hodinky navíc mají málo paměti, takže trasu nemůžou odeslat najednou a posílají ji po dávkách.

`POST /api/1.0/{device}/value` je pro stacionární stanice a nepřijímá polohu, takže trasu z něj složit nejde.

## Navrhovaný endpoint

```
POST /api/1.0/all/route-points
Content-Type: application/json
Authorization: Bearer <token>      (nebo X-API-Key: <klíč>, podle toho, co správce zvolí)
```

Tělo požadavku:

```json
{
  "client_route_id": "garmin-3a9f1c-1791916357-1",
  "batch": 0,
  "final": false,
  "name": "Garmin 13. 10. 2026 18:40",
  "device": "RAYSID",
  "points": [
    [50.0875000, 14.4213000, 1791916357, 0.088, 12.3],
    [50.0875062, 14.4213095, 1791916359, 0.085, 11.8]
  ]
}
```

- `client_route_id`: identifikátor trasy, který vymyslí hodinky (zařízení, čas začátku a pořadí části). První požadavek s novým `client_route_id` založí trasu, další do ní body přidávají.
- `batch`: pořadové číslo dávky v rámci trasy od 0. Když hodinky nedostanou odpověď, pošlou stejnou dávku znovu. Server by ji měl podle dvojice `client_route_id` + `batch` poznat a podruhé neuložit (odpovědět normálně `ok`).
- `final`: `true` u poslední dávky trasy. Server pak může trasu dokončit (přepočet dlaždic, schválení a podobně). Trasa má nejvýš 5000 bodů, pak hodinky začnou novou s dalším `client_route_id`.
- `points`: pole bodů `[lat, lng, čas, µSv/h, cps]`. Čas je unixový v sekundách (UTC). Dávka má typicky 50 bodů.
- `name` a `device` stačí brát z první dávky.

Odpověď:

```json
{ "state": "ok", "route_id": 5790, "points": 150 }
```

Při chybě HTTP 4xx a `{"state": "error", "message": "..."}`. Na 401 hodinky ukážou, že je špatný klíč, a dál neposílají. Na 5xx to zkusí později znovu.

## Přihlášení

Ideální je dlouhodobý klíč uživatele (jako `X-API-Key` u stanic), který se zadá jednou do nastavení aplikace v Garmin Connect. Bearer token z `/login` platí jen 30 dní a musel by se pravidelně přepisovat.
