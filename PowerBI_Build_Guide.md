# Power BI Build Guide — Alfido Tech Customer Behavior Dashboard

This guide walks through turning `Alfido_PowerBI_Data_Model.xlsx` into an interactive
Power BI dashboard. The workbook is already structured as a star schema, so importing
and relating it takes a few minutes.

## 1. Import the data

1. Power BI Desktop → **Get Data → Excel Workbook** → select `Alfido_PowerBI_Data_Model.xlsx`.
2. Load all four sheets: `Fact_Transactions`, `Dim_Customers`, `Dim_Date`, `Segment_Summary`.
3. In Power Query, confirm data types: `PurchaseDate`/`Date` as Date, `Amount`/`Monetary`
   as Decimal Number, ID fields as Whole Number.

## 2. Build the relationships (Model view)

| From | To | Cardinality |
|---|---|---|
| `Fact_Transactions[CustomerID]` | `Dim_Customers[CustomerID]` | Many-to-one |
| `Fact_Transactions[PurchaseDate]` | `Dim_Date[Date]` | Many-to-one |

`Segment_Summary` is a standalone pre-aggregated table for quick KPI cards — no relationship needed.

## 3. Suggested DAX measures

```DAX
Total Revenue = SUM(Fact_Transactions[Amount])

Total Orders = COUNTROWS(Fact_Transactions)

Avg Order Value = DIVIDE([Total Revenue], [Total Orders])

Return Rate = DIVIDE(SUM(Fact_Transactions[Returned]), [Total Orders])

Active Customers = DISTINCTCOUNT(Fact_Transactions[CustomerID])

Customers At Risk (180d+) =
CALCULATE(
    DISTINCTCOUNT(Dim_Customers[CustomerID]),
    Dim_Customers[Recency] > 180
)

Revenue % by Segment =
DIVIDE([Total Revenue], CALCULATE([Total Revenue], ALL(Dim_Customers[RFM_Segment])))
```

## 4. Recommended pages & visuals

**Page 1 — Executive Overview**
- KPI cards: Total Revenue, Total Orders, Avg Order Value, Active Customers
- Line/bar combo chart: Revenue & Orders by `Dim_Date[YearMonth]`
- Donut chart: Revenue by `Dim_Customers[RFM_Segment]`
- Bar chart: Revenue by `Fact_Transactions[ProductCategory]`

**Page 2 — Segment Explorer**
- Table/matrix: one row per `RFM_Segment` with Customers, Avg Recency, Avg Frequency,
  Avg Monetary, Revenue %, Churn Rate (from `Segment_Summary`)
- Scatter chart: `Recency` (x) vs `Monetary` (y), colored by `RFM_Segment`, size by `Frequency`
- Slicer: `RFM_Segment`, `Gender`, `PreferredCategory`

**Page 3 — Retention & Risk**
- Bar chart: `Customers At Risk (180d+)` by `RFM_Segment`
- Table: top at-risk customers by `Monetary`, filtered to `Recency > 180`, sorted descending
- Card: overall `Return Rate`
- Bar chart: Return Rate by `ProductCategory`

**Page 4 — Purchase Patterns**
- Column chart: Orders by `PaymentMethod`
- Column chart: Revenue by `ProductCategory` and `Gender` (clustered)
- Histogram (via grouping/binning on `Dim_Customers[Age]`): customer age distribution

## 5. Formatting tips

- Use a consistent color per RFM segment across every page (set via a color field
  parameter or a manual legend color mapping) so segments are recognizable at a glance.
- Add a top-level slicer/bookmark for date range so the Executive Overview page can be
  filtered by year or quarter.
- Pin the KPI cards row at the top of every page for consistency.

---
*Note: Power BI Desktop was not available in the build environment, so this workbook +
guide gets you to a working dashboard in a few minutes rather than a `.pbix` file directly.*
