COLLECTION PACK — Windows edition
=================================
loop.ps1  — the collection loop (PowerShell port of loop.sh)
queue.txt — the city queue (dublin -> queretaro -> kampala -> nairobi -> lisbon -> madrid)

Setup (PowerShell, one time):
  mkdir C:\Users\kim\contact-collection
  cd C:\Users\kim\contact-collection
  # save loop.ps1 and queue.txt from this page into the folder
  grok -p "say GROK-READY"        (should print GROK-READY)

Run:
  powershell -ExecutionPolicy Bypass -File .\loop.ps1

Stop anytime with Ctrl+C — re-running resumes where it left off.
Results: data\grok-<city>.json, <city>\result.md, loop.log, loop-tally.md.
When tokens run out, runs fail fast and the loop walks on; flip failed->pending
in queue.txt after reset and run again.
