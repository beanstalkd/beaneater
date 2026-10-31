# CHANGELOG for Beaneater

## Unreleased

* `close` while a command is waiting on the connection (a `reserve`, say), whether from a signal handler or from another thread, now makes that command raise `NotConnected`; 1.1.x raised `IOError`, and on Ruby 3.3 and 3.4 a `close` from a signal handler could crash the process. A `close` from a `job_parser` lets its command finish, then closes the socket (@nesquena)
* Drop the connection when a command is interrupted mid-reply (for example by `Timeout.timeout`), so the next command no longer reads the stale reply (reported by @tdegrunt)
* Honour `stop!` while `process!` is waiting for a job with `reserve_timeout` set (reported by @martint17r)
* Keep `process!` running when a handler deletes or releases its job, or overruns its TTR, and then raises; it used to stop with `NotFoundError` or `JobNotReserved` (reported by @pagojo)
* Reconnect on the next command after the connection was lost, restoring the used and watched tubes (while beanstalkd is down each command now retries for about 2 seconds before raising `NotConnected`, and gives up after 3 reconnects when every new connection is dropped at once; set `connect_timeout` in web apps that enqueue during requests), and make `process!` raise `NotConnected` instead of looping while its beanstalkd is down (a handler that raises `NotConnected` for another server still has its job buried, as before) (reported by @b-sridhar and @Meekohi)
* Test on Ruby 2.7 to 3.4 and 4.0 in CI (dropping 2.6), and update `actions/checkout` to v4 (@nesquena)
* Require Ruby 2.7 or newer, declared in the gemspec, so older Rubies get a clear install-time error instead of failing at runtime (the code needs at least 2.5 for `Hash#slice`), #83 (@nesquena; reported by @hkmaly)
* Make `read_timeout` and `write_timeout` take effect: they set `SO_RCVTIMEO`/`SO_SNDTIMEO`, which have no effect on Ruby 3 (Ruby waits on the socket itself), so a server that stopped answering still blocked forever. Beaneater now enforces both itself, adds `read_timeout` to `reserve(timeout)`'s own wait, never cuts off a plain `reserve`, and on timeout raises the new `Beaneater::SocketTimeout` (a `NotConnected`) and drops the connection, so the next command reconnects. `read_timeout` and `write_timeout` may be numeric strings. A `SocketTimeout` on `put` is ambiguous (beanstalkd may have stored the job), so retrying it can enqueue the job twice (@nesquena)
* Fix a raising `job_parser` (e.g. `JSON.parse` on a non-JSON job) leaving the connection one reply out of step, so later commands returned the wrong replies (@nesquena)
* Fix stats and tube lists mangling values since 1.1.2: `-`, `:` and `~` were rewritten to `_`, so `job.tube` for tube `email-jobs` was `"email_jobs"` and `Jobs#process!` buried its jobs; tube names that look like dates or numbers (`2026-10-30`, `1.10`) are now returned as strings instead of raising or being converted (@nesquena)
* Add `connect_timeout` (Ruby 3+), `resolv_timeout` (Ruby 3+), `read_timeout`, and `write_timeout` configuration options (@rveznaver)
* Fix `StatStruct#[]` raising a `SyntaxError` when looking up hyphenated beanstalkd keys (e.g. `stats['current-jobs-ready']`); keys are now underscored before lookup to match how they are stored (@dkam)

## 1.1.4 (March 6 2026)

* Add frozen string literal comments for Ruby 3.4 compatibility (@nearapogee)
* Update tests for Ruby 3.4.x (@nearapogee)
* Add GitHub Actions CI workflow (@Ifiht)
* Update README.md (@Ifiht)

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
