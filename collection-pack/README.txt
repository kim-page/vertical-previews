COLLECTION PACK — Windows edition
=================================
loop.ps1  — the collection loop (PowerShell port of loop.sh)

The queue now lives in the Google Sheet "Queue" tab (schema workbook) —
the loop fetches it fresh before every task, no login needed. Edit the
sheet to reorder cities, skip one, or add a new one; the laptop obeys on
its next cycle. Statuses: Backlog / Doing / Done / Verified / Failed.

Setup (PowerShell, one time):
  mkdir C:\Users\kim\contact-collection
  cd C:\Users\kim\contact-collection
  # save loop.ps1 from this page into the folder
  grok -p "say GROK-READY"        (should print GROK-READY)

Run:
  powershell -ExecutionPolicy Bypass -File .\loop.ps1

Upgrading from the old pack: just replace loop.ps1 and restart the
PowerShell window. Already-finished cities are never re-run.

Stop anytime with Ctrl+C — re-running resumes where it left off.
Results: data\grok-<city>.json, <city>\result.md, loop.log, loop-tally.md.
When tokens run out, runs fail fast and the loop walks on; flip Failed
back to Backlog in the sheet after reset and run again.
