"""Generate an enriched synthetic YPYW estimates dataset.

Takes the base estimates (Document Id, Client Name, Estimate Amount) and adds the
analytics dimensions the BI layer reports on -- estimate date, sales-funnel status,
salesperson, and lead source -- using a fixed seed so the output is reproducible.

The data is SYNTHETIC: client names and amounts mirror the shape of real estimate
exports but contain no real client information. Lead-source win rates and marketing
costs are intentionally differentiated so the dashboard surfaces a genuine ROI
insight (referral/organic leads convert best at the lowest cost).

Output columns match the dbo.RawEstimates table so azure/seed_sample_data.py can
bulk-load the file directly.

Usage:
    python azure/generate_sample_data.py
"""
import csv
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent              # azure/
REPO = HERE.parent                                  # repo root
CSV_FILE = REPO / "ypyw_clean" / "Processed" / "sample_estimates.csv"

SEED = 20250629
random.seed(SEED)

# (LeadSourceId, name, relative lead volume, win rate)  -- IDs match schema.sql seed
LEAD_SOURCES = [
    (1, "Homestars",  0.22, 0.42),
    (2, "Bark",       0.12, 0.22),
    (3, "Facebook",   0.18, 0.28),
    (4, "Google Ads", 0.24, 0.33),
    (5, "Referral",   0.24, 0.55),
]
SALESPEOPLE = [(1, 0.55), (2, 0.45)]          # (SalesPersonId, relative volume) -> Sohail, Ansr
PENDING_RATE = 0.12                            # fraction of estimates still open
MONTH_WEIGHTS = [2, 2, 4, 6, 7, 8, 8, 7, 6, 4, 2, 2]   # Jan..Dec, painting season is heavier


def weighted_choice(items, weights):
    return random.choices(items, weights=weights, k=1)[0]


def read_base(path):
    """Read only the stable base fields so re-runs are deterministic and idempotent."""
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        rows = []
        for raw in reader:
            r = {(k.strip() if k else k): (v.strip() if isinstance(v, str) else v)
                 for k, v in raw.items()}
            rows.append({
                "Document Id": r["Document Id"],
                "Client Name": r["Client Name"],
                "Estimate Amount": r["Estimate Amount"],
            })
    return rows


def enrich(rows):
    ls_ids = [ls[0] for ls in LEAD_SOURCES]
    ls_weights = [ls[2] for ls in LEAD_SOURCES]
    ls_winrate = {ls[0]: ls[3] for ls in LEAD_SOURCES}
    sp_ids = [s[0] for s in SALESPEOPLE]
    sp_weights = [s[1] for s in SALESPEOPLE]
    months = list(range(1, 13))

    for r in sorted(rows, key=lambda x: int(x["Document Id"])):
        lead = weighted_choice(ls_ids, ls_weights)
        salesperson = weighted_choice(sp_ids, sp_weights)
        month = weighted_choice(months, MONTH_WEIGHTS)
        day = random.randint(1, 28)
        if random.random() < PENDING_RATE:
            status = "Pending"
        else:
            status = "Won" if random.random() < ls_winrate[lead] else "Lost"
        r["Estimate Expires Date"] = f"2025-{month:02d}-{day:02d}"
        r["Status"] = status
        r["SalesPersonId"] = salesperson
        r["LeadSourceId"] = lead
    return rows


def main():
    rows = enrich(read_base(CSV_FILE))
    fieldnames = ["Document Id", "Client Name", "Estimate Expires Date",
                  "Status", "Estimate Amount", "SalesPersonId", "LeadSourceId"]
    rows_sorted = sorted(rows, key=lambda x: int(x["Document Id"]))
    with open(CSV_FILE, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows_sorted:
            writer.writerow({k: r[k] for k in fieldnames})
    print(f"Wrote {len(rows_sorted)} enriched rows to {CSV_FILE.name} (seed={SEED}).")


if __name__ == "__main__":
    main()
