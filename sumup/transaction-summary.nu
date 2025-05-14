#!/usr/bin/env nu

# Generate a summary of a "Transactions" export from the SumUp download center
#
# For each combination of "Email" and "Payout ID" it gives you a line that
# contains those and their total, fee and payout amounts.
def main [
  csv_file: string # Path to the CSV input file
] {
  let csv = open $csv_file
  let transaction_ids = ($csv | where "Payout ID" != "" | select "Transaction ID" | uniq)
  let sales = ($csv | where "Transaction type" == "Sale")
  let payouts = ($csv | where "Transaction type" == "Payout")
  $transaction_ids
    | each {|row|
      let sale = ($sales | where "Transaction ID" == ($row | get "Transaction ID") | first)
      let payout = ($payouts | where "Transaction ID" == ($row | get "Transaction ID") | first)
      {
        transaction_id: ($row | get "Transaction ID"),
        payout_id: ($payout | get "Payout ID"),
        total: ($sale | get "Total"),
        fee: ($payout | get "Fee"),
        payout: ($payout | get "Payout"),
        mail: ($sale | get "Email"),
        date: ($sale | get "Date"),
      }
    }
    | group-by payout_id mail --to-table
    | each {|row|
      {
        payout_id: $row.payout_id,
        mail: $row.mail,
        total:  ($row.items | get total  | math sum),
        fee:    ($row.items | get fee    | math sum),
        payout: ($row.items | get payout | math sum),
      }
    }
    | explore
}
