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
      let date = $row | get "Datum der Transaktion" | into datetime --format '%d.%m.%y, %H:%M' | format date '%Y-%m-%d'
      mut notes = [($row | get 'Transaktions-ID')]
      let reference = ($row | get 'Referenz')
      if $reference != '' {
        $notes = $notes | append [$reference]
      }
      let payment_reference = ($row | get 'Zahlungsreferenz')
      if $payment_reference != '' {
        $notes = $notes | append [$payment_reference]
      }
      let common = {
        date:  $date
        description: ($notes | str join " - ")
      }
      match ($row | get "Art der Transaktion") {
        "SumUp Einzahlung" => {
          account: "SumUp"
          value: ($row | get "Rechnungsbetrag eingehend")
        }
        "Ausgehende Banküberweisung" => {
          account: $row.Referenz
          value: (($row | get "Rechnungsbetrag ausgehend") * -1)
        }
        _ => {}
      } | merge $common
    }
    | save -f ($file | str replace '.csv' '.preprocessed.csv')
}
