#!/usr/bin/env nu

# Preprocesses Sumup Business Account CSV exports
#
# The two main problems this solves are:
#  - Instead of all positive values with a row explaining whether they're
#    incoming or outgoing, the values are put into a single field with the
#    proper sign
#  - A few different columns are merged into a "description" that can be used
#    if software doesn't have support for more different fields.
def main [
  file: string # Path to the CSV input file
] {
  open $file
    | each {|row|
      let date = $row | get "Transaction date" | into datetime --format '%d/%m/%Y, %H:%M' | format date '%Y-%m-%d'
      mut notes = [($row | get 'Transaction code')]
      let reference = ($row | get 'Reference')
      if $reference != '' {
        $notes = $notes | append [$reference]
      }
      let payment_reference = ($row | get 'Payment reference')
      if $payment_reference != '' {
        $notes = $notes | append [$payment_reference]
      }
      let common = {
        date:  $date
        description: ($notes | str join " - ")
      }
      match ($row | get "Transaction type") {
        "SumUp pay-in" => {
          account: "SumUp"
          value: ($row | get "Transaction amount in")
        }
        "Outgoing bank transfer" => {
          account: $row.Reference
          value: (($row | get "Transaction amount out") * -1)
        }
        _ => {}
      } | merge $common
    }
    | save -f ($file | str replace '.csv' '.preprocessed.csv')
}
