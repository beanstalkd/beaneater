# CHANGELOG for Beaneater

## 1.1.3 (Oct 14 2022)

* Fixes issue introduced in 1.1.2 re YML parsing (@pond)
* Fix job lookup test so it passes again

## 1.1.2 (Oct 10 2022)

* Fixes beaneater when used with Ruby 3.1 and YAML 4 (@pond)

## 1.1.1 (April 27th 2021)

* Support Ruby 3 keyword arguments (@yahonda)
* Add CI for Ruby 3 (@yahonda)

## 1.1.0 (April 25th 2021)

* 'clear' behavior was failing unexpectedly, swallow issues during delete as well (@bfolkens)
* Fix assigned but unused variables (@utilum)
* Fix last_used tube not stored (@albb0920)
* Fix deprecation warning in ruby 2.7 (@albb0920)
* Fix watched tubes not restored after reconnect (@albb0920)
* Fix keyword arguemnt warning (@albb0920)

## 1.0.0 (April 26th 2015)

* Beginning from version 1.0.0 the support for `Beaneater::Pool` has been dropped (@alup)
* `Jobs#find_all` method has been removed, since it is no longer necessary after removing pool (@alup)
* `Tubes` is now an enumerable allowing `tubes` to be handled as a collection (@Aethelflaed)

## 0.3.3 (August 16th 2014)

* Fix failure when job is not defined and fix exception handling for jobs (@nicholasorenrawlings)
* Add reserve_timeout option to job processing (@nicholasorenrawlings)
* Add travis-ci badge (@tdg5)
* Fix tests to run more reliably (@tdg5)

## 0.3.2 (Sept 15 2013)

* Fix #29 ExpectedCrlfError name and invocation (@tdg5)

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
