#!/usr/bin/env nu

# Aufteilen von Pretix POS Belegen nach MwSt und SumUp Gebühren.
def main [
  pretix: string, # Pfad zum Belegzeilen Export aus pretixPOS im CSV Format
  sumup: string, # Pfad zum Transaktionsbericht aus dem SumUp Download Center im CSV Format
] {
  let sumup_txns = load_sumup_txns $sumup

  open $pretix
    | where "Status" != "CANCELED"
    | group-by "Device ID" "Closing ID" "Receipt ID" "Event slug" --to-table
    | par-each {|txn|
      let vat_sums = $txn.items
        | group-by "Tax rate" --to-table
        | each {|txns_by_rate|
          {
            rate: ("gross_at_vat_" + ($txns_by_rate."Tax rate" | into float | into string --decimals 0)),
            gross: ($txns_by_rate.items | get "Gross price" | math sum)
          }
        }
        | transpose --ignore-titles --header-row --as-record 
      {
        ...$txn,
        ...$vat_sums,
        gross: ($vat_sums | values | math sum),
      }
    }
    | par-each {|txn|
      let payment_type = $txn.items | get "Payment type" | first
      let sumup_details = if $payment_type == "sumup" {
        sumup_detail_for_pretix_txn $sumup_txns $txn
      } else {
        {}
      }
      {
        ...$txn,
        ...$sumup_details,
        payment_type: $payment_type,
      }
    }
    | par-each {|txn|
      {
        device_id: $txn."Device ID",
        closing_id: $txn."Closing ID",
        receipt_id: $txn."Receipt ID",
        event_slug: $txn."Event slug",
        payment_type: $txn.payment_type,
        gross: $txn.gross,
        gross_at_vat_0: ($txn | get gross_at_vat_0 --optional | default 0),
        sumup_fee_for_gross_at_vat_0: ($txn | get sumup_fee_for_gross_at_vat_0 --optional | default 0),
        sumup_payout_for_gross_at_vat_0: ($txn | get sumup_payout_for_gross_at_vat_0 --optional | default 0),
        gross_at_vat_7: ($txn | get gross_at_vat_7 --optional | default 0),
        sumup_fee_for_gross_at_vat_7: ($txn | get sumup_fee_for_gross_at_vat_7 --optional | default 0),
        sumup_payout_for_gross_at_vat_7: ($txn | get sumup_payout_for_gross_at_vat_7 --optional | default 0),
        gross_at_vat_19: ($txn | get gross_at_vat_19 --optional | default 0),
        sumup_fee_for_gross_at_vat_19: ($txn | get sumup_fee_for_gross_at_vat_19 --optional | default 0),
        sumup_payout_for_gross_at_vat_19: ($txn | get sumup_payout_for_gross_at_vat_19 --optional | default 0),
        sumup_email: ($txn | get sumup_email --optional | default ""),
        sumup_id: ($txn | get sumup_id --optional | default ""),
        sumup_error: ($txn | get sumup_error --optional | default null),
      }
    }
    | explore
}

def load_sumup_txns [csv_path] {
  open $csv_path
    | group-by --to-table "Transaktions-ID"
    | where {|txn|
      let payment_types = $txn.items | get "Zahlungsart"
      ("Umsatz" in $payment_types) and ("Auszahlung" in $payment_types) and ("Rückerstattung" not-in $payment_types)
    }
    | each {|txn|
      let id = ($txn.Transaktions-ID)
      let sale = ($txn.items | where "Zahlungsart" == "Umsatz" | first)
      let payout = ($txn.items | where "Zahlungsart" == "Auszahlung" | first)
      {
        email: ($sale."E-Mail"),
        id: $id,
        description: ($sale."Beschreibung"),
        gross: ($sale."Betrag inkl. MwSt."),
        fee: ($sale."Gebühr"),
        payout: ($sale."Auszahlung"),
        payout_id: ($payout."Auszahlungs-ID"),
      }
    }
}

def sumup_detail_for_pretix_txn [sumup_txns, pretix_txn] {
  let expected_sumup_description = $'Beleg ($pretix_txn."Device ID")/($pretix_txn."Receipt ID") ($pretix_txn."Event slug" | str upcase)'
  let sumup_txns = $sumup_txns
    | where "description" == $expected_sumup_description
  if ($sumup_txns | length) != 1 {
    return {
      sumup_error: $'Failed to match "($expected_sumup_description)"'
    }
  }
  let sumup_txn = $sumup_txns | first
  if $sumup_txn.gross != $pretix_txn.gross {
    return {
      sumup_error: $'Gross from pretix order ($pretix_txn."Order") \(($pretix_txn.gross)\) does not match gross from sumup transaction ($sumup_txn.id) \(($sumup_txn.gross)\)'
    }
  }
  let sumup_fee_by_vat = $pretix_txn
    | transpose key value
    | where {|row| $row.key | str starts-with "gross_at_vat_"}
    | each {|row|
      {
        rate: ("sumup_fee_for_" + $row.key),
        fee: (($row.value / $sumup_txn.gross) * $sumup_txn.fee),
      }
    }
    | transpose --ignore-titles --header-row --as-record
  let sumup_payout_by_vat = $pretix_txn
    | transpose key value
    | where {|row| $row.key | str starts-with "gross_at_vat_"}
    | each {|row|
      {
        rate: ("sumup_payout_for_" + $row.key),
        fee: (($row.value / $sumup_txn.gross) * $sumup_txn.payout),
      }
    }
    | transpose --ignore-titles --header-row --as-record
  let sumup_transaction_prefixed = $sumup_txn
    | transpose key value
    | each {|row|
      {
         key: ("sumup_" + $row.key),
         val: $row.value,
      }
    }
    | transpose --ignore-titles --header-row --as-record
  {
    ...$sumup_fee_by_vat,
    ...$sumup_payout_by_vat,
    ...$sumup_transaction_prefixed,
  }
}
