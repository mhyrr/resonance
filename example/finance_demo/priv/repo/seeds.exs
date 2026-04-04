alias FinanceDemo.Repo
alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}

# Clear existing data
Repo.delete_all(Transaction)
Repo.delete_all(Budget)
Repo.delete_all(Category)
Repo.delete_all(Account)

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

# --- Accounts ---
checking = Repo.insert!(%Account{name: "Main Checking", type: "checking", institution: "Chase", balance: 4_250_00, inserted_at: now, updated_at: now})
savings = Repo.insert!(%Account{name: "Emergency Fund", type: "savings", institution: "Marcus", balance: 12_000_00, inserted_at: now, updated_at: now})
credit = Repo.insert!(%Account{name: "Rewards Card", type: "credit", institution: "Amex", balance: -1_830_00, inserted_at: now, updated_at: now})

# --- Categories (2-level hierarchy) ---
make_parent = fn name, color ->
  Repo.insert!(%Category{name: name, color: color, parent_id: nil, inserted_at: now, updated_at: now})
end

make_child = fn name, parent ->
  Repo.insert!(%Category{name: name, color: parent.color, parent_id: parent.id, inserted_at: now, updated_at: now})
end

housing = make_parent.("Housing", "#4F46E5")
food = make_parent.("Food", "#059669")
transport = make_parent.("Transportation", "#D97706")
entertainment = make_parent.("Entertainment", "#DC2626")
utilities = make_parent.("Utilities", "#7C3AED")
health = make_parent.("Health", "#0891B2")
shopping = make_parent.("Shopping", "#E11D48")
income = make_parent.("Income", "#16A34A")

rent = make_child.("Rent", housing)
home_insurance = make_child.("Home Insurance", housing)
groceries = make_child.("Groceries", food)
restaurants = make_child.("Restaurants", food)
coffee = make_child.("Coffee", food)
gas = make_child.("Gas", transport)
car_insurance = make_child.("Car Insurance", transport)
parking = make_child.("Parking", transport)
streaming = make_child.("Streaming", entertainment)
dining_out = make_child.("Dining Out", entertainment)
events = make_child.("Events & Tickets", entertainment)
electric = make_child.("Electric", utilities)
internet = make_child.("Internet", utilities)
phone = make_child.("Phone", utilities)
gym = make_child.("Gym", health)
pharmacy = make_child.("Pharmacy", health)
clothing = make_child.("Clothing", shopping)
electronics = make_child.("Electronics", shopping)
salary = make_child.("Salary", income)
freelance = make_child.("Freelance", income)

# --- Budgets ---
months = for m <- -5..0 do
  date = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: m)
  "#{date.year}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"
end

budget_amounts = %{
  housing => 1_800_00, food => 600_00, transport => 300_00,
  entertainment => 200_00, utilities => 250_00, health => 100_00, shopping => 150_00
}

for {cat, amount} <- budget_amounts, month <- months do
  Repo.insert!(%Budget{category_id: cat.id, month: month, amount: amount, inserted_at: now, updated_at: now})
end

# --- Transactions ---
gen_txn = fn attrs ->
  Repo.insert!(%Transaction{
    amount: attrs.amount, date: attrs.date, description: attrs.description,
    merchant: attrs.merchant, type: attrs.type,
    account_id: attrs.account_id, category_id: attrs.category_id,
    inserted_at: now, updated_at: now
  })
end

today = Date.utc_today()
start_date = Date.shift(today, month: -5) |> Date.beginning_of_month()
total_days = Date.diff(today, start_date)

# Recurring monthly
for month_offset <- 0..5 do
  month_start = Date.shift(start_date, month: month_offset)

  gen_txn.(%{amount: -1_650_00, date: month_start, description: "Monthly rent", merchant: "Landlord", type: "debit", account_id: checking.id, category_id: rent.id})
  gen_txn.(%{amount: -95_00, date: Date.shift(month_start, day: 14), description: "Home insurance premium", merchant: "State Farm", type: "debit", account_id: checking.id, category_id: home_insurance.id})
  gen_txn.(%{amount: -125_00, date: Date.shift(month_start, day: 4), description: "Auto insurance", merchant: "GEICO", type: "debit", account_id: checking.id, category_id: car_insurance.id})
  gen_txn.(%{amount: -15_99, date: Date.shift(month_start, day: 9), description: "Netflix", merchant: "Netflix", type: "debit", account_id: credit.id, category_id: streaming.id})
  gen_txn.(%{amount: -10_99, date: Date.shift(month_start, day: 9), description: "Spotify", merchant: "Spotify", type: "debit", account_id: credit.id, category_id: streaming.id})
  gen_txn.(%{amount: -75_00, date: Date.shift(month_start, day: 19), description: "Internet service", merchant: "Comcast", type: "debit", account_id: checking.id, category_id: internet.id})
  gen_txn.(%{amount: -85_00, date: Date.shift(month_start, day: 21), description: "Phone plan", merchant: "T-Mobile", type: "debit", account_id: checking.id, category_id: phone.id})
  gen_txn.(%{amount: -(Enum.random(80..150) * 100), date: Date.shift(month_start, day: 17), description: "Electric bill", merchant: "ConEd", type: "debit", account_id: checking.id, category_id: electric.id})
  gen_txn.(%{amount: -50_00, date: month_start, description: "Gym membership", merchant: "Planet Fitness", type: "debit", account_id: credit.id, category_id: gym.id})
  gen_txn.(%{amount: 3_200_00, date: month_start, description: "Paycheck", merchant: "Employer", type: "credit", account_id: checking.id, category_id: salary.id})
  gen_txn.(%{amount: 3_200_00, date: Date.shift(month_start, day: 14), description: "Paycheck", merchant: "Employer", type: "credit", account_id: checking.id, category_id: salary.id})
end

# Variable spending
merchants = %{
  groceries => [{"Whole Foods", 45..120}, {"Trader Joe's", 30..80}, {"Costco", 80..200}],
  restaurants => [{"Chipotle", 12..18}, {"Thai Palace", 25..45}, {"Pizza Place", 15..30}],
  coffee => [{"Starbucks", 5..8}, {"Blue Bottle", 6..9}, {"Local Cafe", 4..7}],
  gas => [{"Shell", 35..65}, {"BP", 30..55}],
  dining_out => [{"Olive Garden", 40..80}, {"Sushi Bar", 50..90}],
  parking => [{"ParkMobile", 8..20}, {"City Garage", 15..30}],
  pharmacy => [{"CVS", 10..40}, {"Walgreens", 8..35}],
  clothing => [{"Uniqlo", 30..80}, {"Target", 20..60}],
  electronics => [{"Amazon", 20..150}, {"Best Buy", 50..300}]
}

frequencies = %{
  groceries => 2, restaurants => 2, coffee => 4, gas => 1,
  dining_out => 1, parking => 2, pharmacy => 0.3,
  clothing => 0.2, electronics => 0.1
}

weeks = div(total_days, 7)

for {category, merchant_list} <- merchants,
    _week <- 1..weeks,
    _freq <- 1..max(1, round((frequencies[category] || 0.5) * 1)),
    :rand.uniform() < (frequencies[category] || 0.5) do
  {merchant_name, range} = Enum.random(merchant_list)
  amount = Enum.random(range) * 100
  day_offset = Enum.random(0..total_days)
  date = Date.shift(start_date, day: min(day_offset, total_days))
  account = if amount < 50_00, do: credit, else: Enum.random([checking, credit])

  gen_txn.(%{
    amount: -amount, date: date, description: "#{merchant_name} purchase",
    merchant: merchant_name, type: "debit",
    account_id: account.id, category_id: category.id
  })
end

# Occasional freelance income
for _i <- 1..Enum.random(2..5) do
  gen_txn.(%{
    amount: Enum.random(500..2000) * 100,
    date: Date.shift(start_date, day: Enum.random(0..total_days)),
    description: "Freelance project payment", merchant: "Client", type: "credit",
    account_id: checking.id, category_id: freelance.id
  })
end

# Occasional events
for _i <- 1..Enum.random(3..8) do
  gen_txn.(%{
    amount: -(Enum.random(25..150) * 100),
    date: Date.shift(start_date, day: Enum.random(0..total_days)),
    description: Enum.random(["Concert tickets", "Movie night", "Comedy show", "Sports game"]),
    merchant: Enum.random(["Ticketmaster", "AMC", "StubHub", "Eventbrite"]),
    type: "debit", account_id: credit.id, category_id: events.id
  })
end

txn_count = Repo.aggregate(Transaction, :count, :id)
cat_count = Repo.aggregate(Category, :count, :id)
IO.puts("Seeded: 3 accounts, #{cat_count} categories, #{txn_count} transactions, #{length(months)} months of budgets")
