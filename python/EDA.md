# Executive EDA Roadmap — E-Commerce Gold Layer

**Prepared as:** Senior Director of Data Analytics
**Scope:** Gold layer only (`gold.dim_*`, `gold.fact_*`)
**Purpose:** Answer "What is happening in our business?" with executive-grade, decision-driving analysis — not tutorial-style charts.

---

## 0. Schema Inspection & Assumptions (Read This Before Building Anything)

### Grain of each table

| Table | Grain | Notes |
|---|---|---|
| `dim_customers` | 1 row per `customer_id` | Note: Olist-style schema means `customer_id` is actually an **order-level surrogate**, while `customer_unique_id` is the true person. **This is the single most important modeling decision in the whole warehouse.** |
| `dim_products` | 1 row per `product_id` | Static attributes only, no time dimension |
| `dim_sellers` | 1 row per `seller_id` | Static |
| `dim_date` | 1 row per `date_id` (day) | Calendar dimension |
| `fact_orders` | 1 row per `order_id` | Header-level order facts (status, dates) |
| `fact_order_items` | 1 row per `order_id` + `order_item_id` | **Line-item grain** — an order with 3 products = 3 rows. This is where revenue actually lives. |
| `fact_payments` | 1 row per `order_id` + `payment_sequential` | An order can have **multiple payment rows** (split payments). Summing `payment_value` without grouping by `order_id` first will double count. |
| `fact_reviews` | 1 row per `review_id`, tied to `order_id` | Assume mostly 1:1 with order, but treat as 1:many defensively |

### Critical assumptions and traps to design around

1. **Customer identity trap:** `customer_id` in `dim_customers` is unique per order, not per person. Any "repeat customer," "customer lifetime value," or "customer segmentation" analysis MUST use `customer_unique_id`, never `customer_id`. This will be called out explicitly in every customer-domain EDA.
2. **Revenue double-counting risk:** Revenue must be computed at `fact_order_items` grain (`price + freight_value`), aggregated up to order/customer/category level. `fact_payments.payment_value` is a **different source of truth** (what was actually paid, including installments/interest) and will not always tie exactly to `sum(price+freight)` — this discrepancy is itself a hidden-insight opportunity (see Section 12).
3. **One order → many products → many sellers:** A single order can involve multiple sellers (marketplace model). "Seller revenue" and "order count" are not the same denominator — one order can be counted for multiple sellers. Any seller-level order count must be explicit about this ("orders containing this seller" vs. "orders exclusively fulfilled by this seller").
4. **Order status filtering:** Revenue/KPI analyses must decide up front whether to include cancelled/unavailable orders. Recommended default: **delivered + shipped + invoiced** for revenue, with cancelled/unavailable tracked separately as a risk/ops metric, never silently excluded without disclosure.
5. **Delivery performance requires 3 dates:** `order_date`, `order_delivered_customer_date`, `order_estimated_delivery_date`. Delay = actual − estimated. NULLs in `order_delivered_customer_date` mean **not yet delivered or lost** — must be handled as a distinct bucket, not dropped silently.
6. **Freight is a line-item cost, not an order-level cost:** must be summed across `order_item_id` per order before comparing to order value.
7. **No cost/margin data exists.** True profitability is not computable. All "profitability" analyses are **proxies** (e.g., freight-to-price ratio, discounting behavior via installments) and must be labeled as such — never presented as true margin.
8. **No customer acquisition date / channel data.** "Customer lifetime" is bounded by observed order history only, not true CLV in the marketing sense.
9. **Geography is zip-prefix based**, not lat/long — state-level (`customer_state`, `seller_state`) is the reliable geographic grain; city-level will have messier duplicates.
10. **Time zone / date grain:** `dim_date` gives calendar rollups (year, month, day, month_name) — use this for all seasonality instead of deriving from raw timestamps, to keep fiscal reporting consistent.

---

## 1. Executive Business Overview

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Company Scorecard (single pane) | "How is the business doing, right now?" | The one view every exec opens Monday morning | fact_orders, fact_order_items, fact_payments, fact_reviews, dim_customers | order_id joins across facts | Total revenue, total orders, AOV, active customers, active sellers, avg review score, on-time delivery % | KPI card grid | Health-check in 10 seconds | Easy |
| Revenue & Order Growth Trend | Is the business growing month over month? | Growth is the #1 board-level question | fact_orders, fact_order_items, dim_date | order_date → date_id | MoM revenue growth %, MoM order growth % | Line chart, dual axis | Reveals momentum or stagnation | Easy |
| Delivered vs Cancelled vs Pending Mix | How much revenue is "at risk" of not completing? | Cancelled/undelivered orders are lost or delayed revenue | fact_orders | order_status | % by status | Stacked bar | Flags operational leakage | Easy |
| Customer & Seller Base Size Over Time | Is our marketplace supply and demand growing together? | Two-sided marketplace health | dim_customers, dim_sellers, fact_orders, fact_order_items | customer_unique_id, seller_id | New customers/month, new sellers/month | Dual line chart | Detects supply-demand imbalance | Medium |
| Review Score Health | Are customers happy overall? | Review score is a leading indicator of churn | fact_reviews | order_id | Avg score, % 1-star, % 5-star | KPI + histogram (business-purposed, not generic) | Early warning system | Easy |

---

## 2. Revenue Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Monthly Revenue Trend | How is revenue trending? | Baseline for all forecasting | fact_order_items, fact_orders, dim_date | order_id, order_date→date_id | Sum(price+freight) by month | Line chart | Detects trend/seasonality | Easy |
| YoY Growth by Month | Are we growing faster or slower than last year? | Growth rate matters more than absolute revenue | Same as above | Same | YoY % by month | Line + bar combo | Growth deceleration is an early risk signal | Medium |
| Revenue by State | Where is our revenue geographically concentrated? | Informs regional strategy, logistics investment | fact_order_items, fact_orders, dim_customers | order→customer | Revenue by customer_state | Choropleth map | Identifies core vs emerging markets | Medium |
| Revenue by Category | Which categories drive the business? | Category strategy, inventory priority | fact_order_items, dim_products | product_id | Revenue by category | Bar (sorted) | Identifies category dependence | Easy |
| Revenue Pareto (80/20) | Do 20% of categories/customers drive 80% of revenue? | Concentration = risk and focus area | fact_order_items, dim_products / dim_customers | product_id / customer_unique_id | Cumulative % revenue vs % entities | Pareto chart | Quantifies dependency risk | Medium |
| Long-Tail Category Analysis | How much revenue comes from niche, rarely-ordered categories? | Decides whether to prune catalog or double down on niche | fact_order_items, dim_products | product_id | Revenue & order count by category, ranked | Bar with cumulative line | Flags catalog bloat vs hidden gems | Medium |
| Outlier Transaction Detection | Are there abnormally large orders skewing revenue? | Protects KPI integrity, flags fraud/data errors | fact_order_items | order_id | Order value distribution, z-score/IQR flags | Scatter with flagged outliers | Prevents misleading exec reporting | Medium |
| Revenue Contribution: Repeat vs One-Time Customers | How reliant are we on one-time buyers? | Retention economics | fact_order_items, fact_orders, dim_customers | customer_unique_id | % revenue from customers with >1 order | Stacked bar over time | Reveals retention dependency | Medium |
| Average Basket Value Trend | Is AOV growing, shrinking, or stable? | Pricing/promotion effectiveness | fact_order_items, fact_orders | order_id | Revenue / order count, monthly | Line chart | Signals pricing or mix shift | Easy |
| Revenue by Payment Type | Which payment methods generate the most revenue? | Payment partner negotiation, fee strategy | fact_payments, fact_orders | order_id | Revenue by payment_type | Bar chart | Informs payment-partner priorities | Easy |
| Revenue by Installment Count | Do high-installment orders correlate with higher value? | Credit risk & finance cost planning | fact_payments | order_id | Revenue by installment bucket | Bar chart | Flags reliance on credit-driven demand | Medium |
| Revenue by Seller Concentration | How much of revenue depends on top sellers? | Marketplace supply risk | fact_order_items, dim_sellers | seller_id | Revenue by seller, ranked, cumulative % | Pareto chart | Quantifies single-seller dependency risk | Medium |
| Freight Contribution to Revenue | How much of transaction value is freight vs. product price? | Freight subsidization strategy | fact_order_items | order_id | Freight % of order value | Stacked bar / trend line | May reveal margin erosion via shipping | Medium |

---

## 3. Customer Analysis
*(All customer analyses use `customer_unique_id`, never `customer_id`, per the identity assumption above.)*

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Geographic Distribution of Customers | Where do our customers live? | Market penetration, logistics planning | dim_customers | — | Customer count by state | Map | Reveals core geographic markets | Easy |
| Customer Concentration (Pareto) | Do a few customers drive disproportionate revenue? | B2C should NOT look like B2B concentration — a red flag if it does | fact_order_items, dim_customers | customer_unique_id | Cumulative revenue % by customer rank | Pareto chart | Flags abnormal dependency / possible reseller behavior | Medium |
| Repeat Purchase Rate | What % of customers ever come back? | Core retention KPI for e-commerce | fact_orders, dim_customers | customer_unique_id | % customers with order_count > 1 | KPI + trend | Retention is cheaper than acquisition — sizes the opportunity | Medium |
| Purchase Frequency Distribution | How often do repeat customers buy? | Segments "loyal" vs "occasional" | fact_orders, dim_customers | customer_unique_id | Orders per customer (business-purposed histogram) | Bar (bucketed) | Identifies loyalty tiers for marketing | Medium |
| High-Value Customer Identification | Who are our top customers by spend? | VIP program design, retention prioritization | fact_order_items, dim_customers | customer_unique_id | Total spend per customer, ranked | Ranked table/bar | Enables targeted retention investment | Easy |
| RFM-Style Segmentation (Recency, Frequency, Monetary) | Which customers are "champions" vs "at risk" vs "lost"? | Foundation for CRM/marketing action | fact_orders, fact_order_items, dim_customers, dim_date | customer_unique_id | Recency, frequency, monetary tertiles/quintiles | Segmented scatter/heatmap | Directly actionable marketing segments | Advanced |
| Regional Differences in Basket Size | Do customers in different states spend differently? | Region-specific promotions | fact_order_items, fact_orders, dim_customers | customer_unique_id | AOV by state | Bar/map | Informs regional pricing/promo strategy | Medium |
| New vs Returning Customer Revenue Split Over Time | Is growth coming from new acquisition or retention? | Distinguishes healthy growth from acquisition-fueled churn-masking | fact_orders, fact_order_items, dim_customers, dim_date | customer_unique_id | Revenue split by first-time vs returning, monthly | Stacked area chart | Reveals true growth engine | Advanced |

---

## 4. Product Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Top Categories by Revenue & Volume | What sells? | Core merchandising input | fact_order_items, dim_products | product_id | Revenue, order count by category | Dual bar chart | Prioritizes catalog investment | Easy |
| Underperforming Categories | What's dragging the catalog down? | Pruning / repositioning decisions | fact_order_items, dim_products | product_id | Bottom N categories by revenue & review score | Ranked table | Identifies candidates to deprioritize | Easy |
| Category Review Score Comparison | Which categories have quality/satisfaction issues? | Quality control prioritization | fact_order_items, dim_products, fact_reviews | product_id, order_id | Avg review score by category | Bar chart (sorted) | Flags category-specific quality problems | Medium |
| Category Freight Cost Burden | Which categories are expensive to ship? | Pricing/logistics strategy per category | fact_order_items, dim_products | product_id | Avg freight/price ratio by category | Bar chart | Identifies categories needing freight-inclusive pricing | Medium |
| Product Size/Weight vs Freight Cost | Does physical size drive shipping cost as expected? | Validates freight pricing model | fact_order_items, dim_products | product_id | Correlation of weight/volume to freight_value | Scatter with trend line (business-purposed) | Validates or challenges freight pricing logic | Medium |
| Heavy & Oversized Product Flagging | Which products are disproportionately costly to fulfill? | Logistics cost control, packaging strategy | dim_products, fact_order_items | product_id | Weight/volume outliers vs freight incurred | Ranked table | Identifies fulfillment cost outliers | Medium |
| Category Profitability Proxy (Freight-adjusted) | Which categories look attractive after shipping cost? | True profitability proxy without cost data | fact_order_items, dim_products | product_id | (price − freight) as % of price, by category | Bar chart | Reframes "top category" once freight is considered | Advanced |
| Long-Tail Product Analysis | How many products drive almost no revenue? | Catalog rationalization | fact_order_items, dim_products | product_id | Distribution of revenue per product_id | Cumulative/Pareto chart | Supports SKU rationalization decisions | Medium |

---

## 5. Seller Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Seller Revenue Ranking | Who are our top sellers? | Key account management | fact_order_items, dim_sellers | seller_id | Revenue by seller | Ranked bar | Identifies who to nurture/protect | Easy |
| Seller Order Volume vs Revenue | Do high-volume sellers also drive high revenue? | Distinguishes "busy" from "valuable" sellers | fact_order_items, dim_sellers | seller_id | Order count vs revenue per seller | Scatter (business-purposed) | Flags high-volume/low-value sellers | Medium |
| Seller Review Score Distribution | Are certain sellers dragging down customer satisfaction? | Seller quality management | fact_order_items, fact_reviews, dim_sellers | order_id, seller_id | Avg review score by seller | Ranked table | Targets sellers for quality intervention | Medium |
| Seller Delivery Performance | Which sellers consistently ship late? | Operational accountability | fact_order_items, fact_orders, dim_sellers | order_id, seller_id | Avg delay (actual − estimated) by seller | Ranked bar | Identifies sellers needing SLA enforcement | Medium |
| Seller Geographic Concentration | Where are our sellers based vs. our customers? | Supply chain / logistics network planning | dim_sellers, dim_customers | (no direct join — compared side by side) | Seller count by state vs customer count by state | Dual map | Reveals supply-demand geographic mismatch | Medium |
| Seller Revenue Pareto | How dependent is the business on top sellers? | Marketplace concentration risk | fact_order_items, dim_sellers | seller_id | Cumulative revenue % by seller rank | Pareto chart | Quantifies "what if we lost our top seller" risk | Medium |
| Bottom Sellers by Rating & Delay | Which sellers are hurting the platform's reputation? | Seller offboarding/improvement candidates | fact_order_items, fact_orders, fact_reviews, dim_sellers | order_id, seller_id | Composite score: rating + delay | Ranked table | Direct action list for seller ops team | Advanced |

---

## 6. Order Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Order Status Breakdown | What % of orders complete successfully? | Core operational health metric | fact_orders | — | % by order_status | Bar/donut | Flags fulfillment issues | Easy |
| Cancellation Trend Over Time | Is our cancellation rate improving or worsening? | Early warning for ops/inventory problems | fact_orders, dim_date | order_date→date_id | % cancelled by month | Line chart | Detects emerging operational issues | Easy |
| Delivery Lead Time Distribution | How long does it typically take to deliver? | Sets customer expectations, SLA benchmark | fact_orders | — | order_delivered − order_date (business-purposed distribution, not generic histogram) | Bar (bucketed) | Basis for SLA commitments | Easy |
| Estimated vs Actual Delivery Gap | Are we over- or under-promising delivery? | Customer trust & satisfaction driver | fact_orders | — | actual − estimated delivery date | Line/bar trend over time | Reveals systemic over/under-promising | Medium |
| Weekend vs Weekday Purchase Behavior | When do customers actually buy? | Staffing, marketing send-time optimization | fact_orders, dim_date | order_date→date_id | Order count by day-of-week | Bar chart | Optimizes ops staffing and campaign timing | Easy |
| Monthly Seasonality of Orders | Are there predictable seasonal peaks? | Inventory & staffing planning, forecast input | fact_orders, dim_date | order_date→date_id | Order count by month, multi-year overlay | Seasonal line chart | Enables proactive peak-season planning | Medium |

---

## 7. Payment Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Payment Method Mix | How do customers prefer to pay? | Payment partnership & fee negotiation | fact_payments | — | % of orders by payment_type | Donut/bar | Informs which payment rails to invest in | Easy |
| Installment Behavior Distribution | How many installments do customers typically choose? | Credit exposure & partner cost planning | fact_payments | — | Distribution of installment count (business-purposed) | Bar chart | Reveals reliance on credit-based purchasing | Easy |
| Payment Value vs Order Value Reconciliation | Does what customers paid match what was ordered? | Data integrity / potential discount or interest effects | fact_payments, fact_order_items | order_id | Sum(payment_value) vs sum(price+freight) per order | Scatter/diff distribution | Surfaces systemic payment-order mismatches | Advanced |
| High-Installment Customer Behavior | Do high-installment customers behave differently (AOV, return rate proxy via reviews)? | Segments credit-dependent customer base | fact_payments, fact_order_items, fact_reviews | order_id | AOV & review score by installment bucket | Grouped bar | Flags potential credit-risk segment | Medium |
| Revenue by Payment Method Over Time | Are payment preferences shifting? | Anticipates infrastructure needs | fact_payments, fact_orders, dim_date | order_id, order_date→date_id | Revenue by payment_type, monthly | Stacked area chart | Detects payment behavior shifts early | Medium |

---

## 8. Review Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Overall Review Score Trend | Is customer satisfaction improving or declining? | Leading indicator of retention/churn | fact_reviews, dim_date | review_creation_date→date_id | Avg score by month | Line chart | Early churn warning system | Easy |
| Review Score by Category | Which product categories dissatisfy customers most? | Quality control targeting | fact_reviews, fact_order_items, dim_products | order_id, product_id | Avg score by category | Ranked bar | Prioritizes QA investigation by category | Medium |
| Review Score by Seller | Which sellers need intervention? | Seller performance management | fact_reviews, fact_order_items, dim_sellers | order_id, seller_id | Avg score by seller | Ranked table | Direct seller-ops action list | Medium |
| Review Score by State | Are certain regions systematically less satisfied? | May reveal regional logistics/quality issues | fact_reviews, fact_orders, dim_customers | order_id, customer_id | Avg score by customer_state | Map | Flags regional service gaps | Medium |
| Review Score vs Delivery Delay | Does late delivery directly hurt satisfaction? | Quantifies the cost of poor logistics | fact_reviews, fact_orders | order_id | Avg score by delay bucket | Bar chart | Justifies logistics investment with satisfaction $-impact | Medium |
| Review Score vs Payment Type | Does payment method correlate with satisfaction? | Explores non-obvious satisfaction drivers | fact_reviews, fact_payments | order_id | Avg score by payment_type | Bar chart | May reveal friction in specific payment experiences | Medium |
| Review Response Time Analysis | How quickly are reviews submitted after delivery, and does that correlate with sentiment? | Process/engagement insight | fact_reviews, fact_orders | order_id | review_creation_date − order_delivered_customer_date vs score | Scatter | Fast negative reviews may signal urgent issues | Advanced |

---

## 9. Logistics Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Freight Cost Trend Over Time | Is shipping getting more expensive? | Cost control, pricing strategy | fact_order_items, dim_date | shipping_limit_date→date_id | Avg freight_value by month | Line chart | Flags rising logistics costs early | Easy |
| Freight vs Product Size/Weight | Is freight pricing proportionate to product characteristics? | Validates carrier pricing / internal freight model | fact_order_items, dim_products | product_id | Correlation freight vs weight/volume | Scatter (purposed) | Identifies mispriced freight segments | Medium |
| Freight Cost by State | Is shipping to certain states disproportionately expensive? | Regional logistics network investment case | fact_order_items, fact_orders, dim_customers | order_id, customer_id | Avg freight by customer_state | Map | Justifies regional warehouse/hub investment | Medium |
| Delivery Delay by State | Which regions have chronic delivery problems? | Prioritizes logistics network investment | fact_orders, dim_customers | customer_id | Avg delay by state | Map | Direct input to logistics expansion roadmap | Medium |
| Shipping Efficiency: Seller-to-Delivery Lag | Where does the delay actually occur — seller dispatch or carrier transit? | Determines if the fix is seller-side or carrier-side | fact_order_items, fact_orders | order_id | shipping_limit_date vs order_delivered_customer_date | Bar/box (purposed) | Pinpoints where in the chain delay originates | Advanced |
| Estimated Delivery Accuracy Over Time | Is our delivery estimate model improving? | Trust and expectation-setting | fact_orders, dim_date | order_date→date_id | % orders delivered within estimate, monthly | Line chart | Tracks whether ops improvements are working | Medium |

---

## 10. Geographic Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Customer Demand Map | Where is demand? | Foundational for expansion decisions | dim_customers, fact_order_items | customer_id | Revenue/orders by state | Choropleth | Identifies core vs. underserved markets | Easy |
| Seller Supply Map | Where is supply? | Foundational for expansion decisions | dim_sellers, fact_order_items | seller_id | Revenue/orders by seller state | Choropleth | Identifies supply concentration | Easy |
| Supply vs Demand Gap by State | Which states have demand but insufficient local sellers? | Seller-recruitment prioritization | dim_customers, dim_sellers, fact_order_items | customer/seller state comparison | Demand − supply index by state | Diverging bar/map | Direct input to seller acquisition strategy | Advanced |
| Delivery Performance by State | Where is logistics failing customers? | Prioritizes ops investment | fact_orders, dim_customers | customer_id | Avg delay/on-time % by state | Map | Targets underperforming regions | Medium |
| Review Score by Geography | Are certain regions structurally less satisfied? | Regional service quality | fact_reviews, fact_orders, dim_customers | order_id, customer_id | Avg score by state | Map | Flags region-specific service issues | Medium |
| Freight Cost by Geography | Where is shipping most expensive? | Regional pricing/logistics investment case | fact_order_items, dim_customers | customer_id | Avg freight by state | Map | Supports regional hub investment case | Medium |

---

## 11. Risk Analysis

| EDA Title | Business Question | Why It Matters | Gold Views Required | Join Logic | Metrics | Recommended Visualization | Executive Insight | Difficulty |
|---|---|---|---|---|---|---|---|---|
| Revenue Concentration Risk | What % of revenue relies on top 1%/5%/10% of customers? | Quantifies customer-side dependency risk | fact_order_items, dim_customers | customer_unique_id | Cumulative revenue % by customer decile | Pareto/Lorenz curve | Board-level dependency risk metric | Medium |
| Seller Concentration Risk | What happens if we lose our top seller(s)? | Marketplace supply risk | fact_order_items, dim_sellers | seller_id | Revenue % held by top N sellers | Pareto chart | Direct "what-if" risk quantification | Medium |
| Category Dependence Risk | How exposed are we to a single category's demand shifting? | Diversification assessment | fact_order_items, dim_products | product_id | Revenue % by top categories | Bar/Pareto | Flags over-reliance on one category | Easy |
| Payment Method Dependence | How exposed are we if one payment partner has an outage/policy change? | Business continuity planning | fact_payments | — | Revenue % by payment_type | Bar chart | Highlights single-point-of-failure risk | Easy |
| Operational Bottleneck Identification | Where in the order lifecycle do most failures/delays cluster? | Prioritizes ops fixes with highest ROI | fact_orders, fact_order_items | order_id | Delay/cancellation rate by stage proxy | Funnel/bar | Focuses limited ops resources correctly | Advanced |
| Geographic Concentration Risk | Are we overly dependent on one region for revenue? | Regional economic/regulatory exposure | fact_order_items, dim_customers | customer_id | Revenue % by top states | Bar/map | Flags regional over-exposure | Easy |

---

## 12. Hidden Insights (Principal Data Scientist Lens)

These are the analyses that separate a portfolio project from a generic tutorial. None of them are "obvious dashboard tiles" — each requires connecting two things executives don't normally look at together.

1. **Delivery delay elasticity of review score** — is there a delay threshold (e.g., 3 days late) beyond which satisfaction collapses non-linearly rather than gradually?
2. **Freight-to-price ratio as a hidden churn driver** — do customers who paid disproportionately high freight relative to item price leave lower reviews even when delivery was on time?
3. **Installment count vs. review score** — do customers who split payments into many installments report lower satisfaction (financial stress proxy)?
4. **Seller "sweet spot" size** — is there an optimal seller order-volume range where review scores peak, with both very small and very large sellers underperforming?
5. **Category-level freight subsidization** — are certain categories effectively "sold at a loss" once freight is considered relative to price, masked by strong unit revenue?
6. **Regional promise-gap** — do specific states have systematically over-optimistic estimated delivery dates (large estimate-vs-actual gap) independent of actual transit distance?
7. **Payment-value vs. order-value drift over time** — is the gap between what's ordered (price+freight) and what's paid (payment_value) widening, suggesting increasing use of interest/installments as a revenue lever or a data quality issue?
8. **"Silent churn" cohorts** — customers with a single high-value order and no repeat, isolated by state/category, to find where the funnel leaks the most valuable one-time buyers.
9. **Product weight/size vs. review score** — do heavy/oversized products get systematically lower reviews (packaging damage proxy) regardless of category?
10. **Multi-seller order friction** — do orders sourced from multiple sellers have worse delivery performance or lower review scores than single-seller orders?
11. **Day-of-week delivery performance** — are orders placed on certain days of the week systematically delivered later (operational scheduling artifact)?
12. **Review timing bimodality** — do very fast reviews (submitted within a day of delivery) skew more negative or more positive than reviews submitted after a longer gap, revealing different customer motivations to review?
13. **Category cyclicality vs. company-wide seasonality** — do specific categories move opposite to overall seasonal trends (counter-cyclical categories worth marketing during off-peak company seasons)?
14. **Seller geographic-customer distance proxy vs. delay** — using zip-prefix distance between seller and customer as a rough proxy, does distance predict delay better than seller identity itself?
15. **High-frequency low-value vs. low-frequency high-value customer profitability proxy** — which customer behavior pattern actually contributes more cumulative revenue over the observed window?
16. **Order size (number of items) vs. review score** — do larger, multi-item orders have higher failure/dissatisfaction rates than single-item orders?
17. **Price-point clustering and psychological pricing** — do sellers cluster prices at certain thresholds (e.g., just under round numbers), and does this correlate with order volume?
18. **Category-level installment reliance** — are certain categories disproportionately purchased via high-installment plans (indicating price-sensitive or aspirational purchases)?
19. **Weekend order fulfillment penalty** — are weekend-placed orders processed/shipped slower than weekday orders due to operational staffing gaps?
20. **New-seller "onboarding dip"** — do newly active sellers show a temporary dip in review scores/delivery performance in their first few months, suggesting a need for onboarding support programs?
21. **Cross-state seller-customer pairs revenue concentration** — are there specific seller-state → customer-state corridors that dominate revenue disproportionately, suggesting logistics-lane specific investment opportunities?
22. **Estimated delivery date "padding" trend** — is the business quietly increasing estimated delivery windows over time to artificially improve on-time delivery %, masking true operational stagnation?

---

# Prioritization

## Must Have
Executive Business Overview (all 5), Monthly Revenue Trend, Revenue by Category, Revenue by State, Repeat Purchase Rate, Order Status Breakdown, Delivery Lead Time Distribution, Payment Method Mix, Overall Review Score Trend, Seller Revenue Ranking, Revenue Concentration Risk, Seller Concentration Risk.

## Good to Have
YoY Growth, Revenue Pareto, AOV Trend, Customer Concentration, High-Value Customer Identification, Category Review Score Comparison, Seller Delivery Performance, Freight Cost Trend, Delivery Delay by State, Cancellation Trend, Review Score vs Delivery Delay, Payment Value vs Order Value Reconciliation.

## Advanced
RFM-Style Segmentation, New vs Returning Revenue Split, Category Profitability Proxy, Supply vs Demand Gap by State, Operational Bottleneck Identification, Shipping Efficiency Seller-to-Delivery Lag, Bottom Sellers Composite Score, Review Response Time Analysis, all 22 Hidden Insights.

---

# FINAL DELIVERABLE — Top 30 EDA Analyses, Ranked

| # | EDA | Why It Matters / Business Decision | Stakeholders | Gold Views |
|---|---|---|---|---|
| 1 | Company Scorecard | Single source of truth for overall health; frames every other conversation | CEO, all | fact_orders, fact_order_items, fact_payments, fact_reviews, dim_customers |
| 2 | Monthly Revenue Trend | Detects growth/decline before it becomes a crisis | CEO, Finance | fact_order_items, fact_orders, dim_date |
| 3 | YoY Growth by Month | Distinguishes real growth from seasonal noise | CEO, Finance | fact_order_items, fact_orders, dim_date |
| 4 | Revenue Concentration Risk (customers) | Board-level risk metric; informs retention investment | CEO, Finance, Marketing | fact_order_items, dim_customers |
| 5 | Seller Concentration Risk | Quantifies "what if we lose a top seller" exposure | CEO, Operations | fact_order_items, dim_sellers |
| 6 | Repeat Purchase Rate | Core retention KPI; sizes the CRM opportunity | CEO, Marketing | fact_orders, dim_customers |
| 7 | Revenue by Category | Drives merchandising and inventory prioritization | Product, Marketing | fact_order_items, dim_products |
| 8 | Revenue by State / Demand Map | Informs regional expansion and logistics investment | CEO, Operations, Logistics | fact_order_items, dim_customers |
| 9 | Order Status Breakdown | Baseline operational health; flags fulfillment leakage | Operations, CEO | fact_orders |
| 10 | Cancellation Trend Over Time | Early warning for inventory/ops breakdowns | Operations | fact_orders, dim_date |
| 11 | Delivery Lead Time Distribution | Sets realistic SLAs and customer expectations | Operations, Logistics | fact_orders |
| 12 | Estimated vs Actual Delivery Gap | Directly ties to trust and satisfaction | Logistics, CEO | fact_orders |
| 13 | Overall Review Score Trend | Leading churn indicator | CEO, Product, Marketing | fact_reviews, dim_date |
| 14 | Review Score vs Delivery Delay | Quantifies $ cost of poor logistics in satisfaction terms | Logistics, CEO | fact_reviews, fact_orders |
| 15 | Seller Revenue Ranking | Key account management priorities | Sales, Operations | fact_order_items, dim_sellers |
| 16 | Seller Delivery Performance | Enforces SLA accountability across marketplace | Operations | fact_order_items, fact_orders, dim_sellers |
| 17 | Category Review Score Comparison | Targets quality control investigation | Product, Operations | fact_reviews, fact_order_items, dim_products |
| 18 | Freight Cost by State | Justifies regional warehouse/hub investment | Logistics, Finance | fact_order_items, dim_customers |
| 19 | Payment Method Mix | Guides payment partner strategy and fee negotiation | Finance, Product | fact_payments |
| 20 | Revenue Pareto (customers/categories) | Frames concentration for both risk and focus | CEO, Finance | fact_order_items, dim_customers/dim_products |
| 21 | AOV Trend | Signals pricing/promotion/mix effectiveness | Marketing, Finance | fact_order_items, fact_orders |
| 22 | High-Value Customer Identification | Basis for VIP/retention program design | Marketing, Sales | fact_order_items, dim_customers |
| 23 | Category Freight Cost Burden | Informs freight-inclusive pricing per category | Product, Finance | fact_order_items, dim_products |
| 24 | Supply vs Demand Gap by State | Prioritizes seller recruitment by region | Operations, Sales | dim_customers, dim_sellers, fact_order_items |
| 25 | RFM-Style Customer Segmentation | Actionable CRM/marketing segments | Marketing | fact_orders, fact_order_items, dim_customers, dim_date |
| 26 | Category Profitability Proxy (freight-adjusted) | Challenges "top category" assumptions once freight is netted | Finance, Product | fact_order_items, dim_products |
| 27 | Payment Value vs Order Value Reconciliation | Surfaces data integrity or hidden discount/interest effects | Finance | fact_payments, fact_order_items |
| 28 | New vs Returning Customer Revenue Split | Distinguishes healthy growth from acquisition-fueled churn masking | CEO, Marketing, Finance | fact_orders, fact_order_items, dim_customers, dim_date |
| 29 | Shipping Efficiency: Seller-to-Delivery Lag | Pinpoints whether delay is seller-side or carrier-side | Logistics, Operations | fact_order_items, fact_orders |
| 30 | Delivery Delay Elasticity of Review Score (Hidden Insight #1) | Finds the exact threshold where satisfaction collapses — precise, actionable ops target | CEO, Operations, Logistics | fact_reviews, fact_orders |

---

*Next steps available on request: SQL/Python implementation for any of the above, dashboard wireframes, or a forecasting layer built on top of the "Must Have" tier.*