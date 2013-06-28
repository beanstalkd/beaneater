# CHANGELOG for Beaneater

## 0.3.2 (Unreleased)

## 0.3.1 (Jun 28 2013)

* Fixes issue with "chomp" nil exception when losing connection (Thanks @simao)
* Better handling of unknown or invalid commands during transmit
* Raise proper CRLF exception (Thanks @carlosmoutinho)

## 0.3.0 (Jan 23 2013)

* Replace Telnet with tcpsocket thanks @vidarh

## 0.2.2 (Dec 2 2012)

* Fixes status and ID parsing in a response (Thanks @justincase)

## 0.2.1 (Dec 1 2012)

* Convert command to ASCII_8Bit to avoid gsub issues

## 0.2.0 (Nov 12 2012)
* Fix 1.8.7 compatibility issues
* Add configuration block to beaneater and better job parsing
* BREAKING: json jobs now return as string by default not hashes

## 0.1.2 (Nov 7 2012)

* Add timeout: false to transmit to allow longer reserve

## 0.1.1 (Nov 4 2012)

* Add `Jobs#find_all` to fix #10
* Fixed issue with `tubes-list` by merging results
* Add `Job#ttr`, `Job#pri`, `Job#delay`
* Improved yardocs coverage and accuracy

## 0.1.0 (Nov 1 2012)

* Initial release!
