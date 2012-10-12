# Beanstalkd

## Protocol

### Description

The beanstalk protocol runs over TCP using ASCII encoding. Clients connect, send commands and data, wait for responses, and close the connection. For each connection, the server processes commands serially in the order in which they were received and sends responses in the same order. All integers in the protocol are formatted in decimal and (unless otherwise indicated) nonnegative.

### Name convention

Names only supports ASCII strings.

#### Characters Allowed

* **letters** (A-Z and a-z)
* **numerals** (0-9)
* **hyphen** ("-")
* **plus** ("+")
* **slash** ("/")
* **semicolon** (";")
* **dot** (".")
* **dollar-sign** ("$")
* **underscore** ("_")
* **parentheses** ("*(*" and "*)*")

**Notice:** They may not begin with a hyphen and they are terminated by white space (either a space char or end of line). Each name must be at least one character long.

### Errors

| Errors              | Description   |
| --------------------| ------------- |
| `OUT_OF_MEMORY\r\n` | The server cannot allocate enough memory for the job. The client should try again later.|
| `INTERNAL_ERROR\r\n` | This indicates a bug in the server. It should never happen. If it does happen, please report it at http://groups.google.com/group/beanstalk-talk. |
| `BAD_FORMAT\r\n` | The client sent a command line that was not well-formed. This can happen if the line does not end with \r\n, if non-numeric characters occur where an integer is expected, if the wrong number of arguments are present, or if the command line is mal-formed in any other way. |
| `UNKNOWN_COMMAND\r\n` | The client sent a command that the server does not know. |


### Job Lifecycle

A job in beanstalk gets created by a client with the `put` command. During its life it can be in one of four states:

| Status              | Description   |
| --------------------| ------------- |
| `ready`             | it waits in the ready queue until a worker comes along and runs the "reserve" command |
| `reserved`          | if this job is next in the queue, it will be reserved for the worker. The worker will execute the job |
| `delayed`           | when it's waiting "x" seconds before to be `ready` |
| `buried`            | when it is finished the worker will send a "delete" ; when it is finished the worker will send a "delete" |



Here is a picture of the typical job lifecycle:

```
   put            reserve               delete
  -----> [READY] ---------> [RESERVED] --------> *poof*
```



Here is a picture with more possibilities:

```
   put with delay               release with delay
  ----------------> [DELAYED] <------------.
                        |                   |
                        | (time passes)     |
                        |                   |
   put                  v     reserve       |       delete
  -----------------> [READY] ---------> [RESERVED] --------> *poof*
                       ^  ^                |  |
                       |   \  release      |  |
                       |    `-------------'   |
                       |                      |
                       | kick                 |
                       |                      |
                       |       bury           |
                    [BURIED] <---------------'
                       |
                       |  delete
                        `--------> *poof*
```

### Tubes

The system has one or more tubes. Each tube consists of a ready queue and a delay queue. Each job spends its entire life in one tube. Consumers can show interest in tubes by sending the `watch` command; they can show disinterest by sending the `ignore` command. This set of interesting tubes is said to be a consumer's `watch list`. When a client reserves a job, it may come from any of the tubes in its watch list.

When a client connects, its watch list is initially just the tube named `default`. If it submits jobs without having sent a `use` command, they will live in the tube named `default`.

Tubes are created on demand whenever they are referenced. If a tube is empty (that is, it contains no `ready`, `delayed`, or `buried` jobs) and no client refers to it, it will be deleted.

## Commands

### Producer Commands

#### `put` command

The `put` command is for any process that wants to insert a job into the queue. It comprises a command line followed by the job body:

```
put <pri> <delay> <ttr> <bytes>\r\n
<data>\r\n
```

#####`put` options

It inserts a job into the client's currently used tube (see the `use` command below).

* `<pri>` is an integer < 2**32. Jobs with smaller priority values will be scheduled before jobs with larger priorities. The most urgent priority is 0;the least urgent priority is 4,294,967,295.

* `<delay>` is an integer number of seconds to wait before putting the job in the ready queue. The job will be in the "delayed" state during this time.

* `<ttr>` -- time to run -- is an integer number of seconds to allow a worker to run this job. This time is counted from the moment a worker reserves this job. If the worker does not delete, release, or bury the job within `<ttr>` seconds, the job will time out and the server will release the job. The minimum ttr is 1. If the client sends 0, the server will silently increase the ttr to 1.

* `<bytes>` is an integer indicating the size of the job body, not including the trailing "\r\n". This value must be less than max-job-size (default: 2**16).

* `<data>` is the job body -- a sequence of bytes of length <bytes> from the previous line.


##### `put` responses
After sending the command line and body, the client waits for a reply, which
may be:

 * `INSERTED <id>\r\n` to indicate success. `<id>` is the integer id of the new job

 * `BURIED <id>\r\n` if the server ran out of memory trying to grow the priority queue data structure. `<id>` is the integer id of the new job

 * `EXPECTED_CRLF\r\n` The job body must be followed by a CR-LF pair, that is, `"\r\n"`. These two bytes are not counted in the job size given by the client in the put command line.

 * `JOB_TOO_BIG\r\n` The client has requested to put a job with a body larger than max-job-size bytes.

 * `DRAINING\r\n` This means that the server has been put into "drain mode" and is no longer accepting new jobs. The client should try another server or disconnect and try again later.

#### `use` command

The `use` command is for producers. Subsequent put commands will put jobs into the tube specified by this command. If no use command has been issued, jobs will be put into the tube named `default`.

```
use <tube>\r\n
```

##### `use` options

 * `<tube>` is a name at most 200 bytes. It specifies the tube to use. If the tube does not exist, it will be created.

##### `use` responses

* `USING <tube>\r\n` -- `<tube>` is the name of the tube now being used.

#### Worker Commands

A process that wants to consume jobs from the queue uses those commands:

* `reserve`
* `delete`
* `release`
* `bury`


#### `reserve` command

```
reserve\r\n
```

Alternatively, you can specify a timeout as follows:

```
reserve-with-timeout <seconds>\r\n
```

This will return a newly-reserved job. If no job is available to be reserved, beanstalkd will wait to send a response until one becomes available. Once a job is reserved for the client, the client has limited time to run (TTR) the job before the job times out. When the job times out, the server will put the job back into the ready queue. Both the TTR and the actual time left can be found in response to the `stats-job` command.

A timeout value of `0` will cause the server to immediately return either a response or `TIMED_OUT`.  A positive value of timeout will limit the amount of time the client will block on the reserve request until a job becomes available.

##### `reserve` responses

###### Non-succesful responses

* `DEADLINE_SOON\r\n` During the TTR of a reserved job, the last second is kept by the server as a safety margin, during which the client will not be made to wait for another job. If the client issues a reserve command during the safety margin, or if the safety margin arrives while the client is waiting on a reserve command.

* `TIMED_OUT\r\n` If a non-negative timeout was specified and the timeout exceeded before a job became available, the server will respond with TIMED_OUT.

Otherwise, the only other response to this command is a successful reservation
in the form of a text line followed by the job body:

####### Succesful response


```
RESERVED <id> <bytes>\r\n
<data>\r\n
```

 * `<id>` is the job id -- an integer unique to this job in this instance of beanstalkd.

 * `<bytes>` is an integer indicating the size of the job body, not including the trailing `\r\n"`.

 * `<data>` is the job body -- a sequence of bytes of length <bytes> from the previous line. This is a verbatim copy of the bytes that were originally sent to the server in the put command for this job.

#### `delete` command

The delete command removes a job from the server entirely. It is normally used by the client when the job has successfully run to completion. A client can delete jobs that it has `reserved`, `ready` jobs, `delayed` jobs, and jobs that are
`buried`. The delete command looks like this:

```
delete <id>\r\n
```

##### `delete` options

* `<id>` is the job id to delete.

##### `delete` responses

The client then waits for one line of response, which may be:

 * `DELETED\r\n` to indicate success.

 * `NOT_FOUND\r\n` if the job does not exist or is not either reserved by the client, ready, or buried. This could happen if the job timed out before the client sent the delete command.

#### `release` command

The release command puts a `reserved` job back into the ready queue (and marks its state as `ready`) to be run by any client. It is normally used when the job fails because of a transitory error. It looks like this:

```
release <id> <pri> <delay>\r\n
```

##### `release` options

 * `<id>` is the job id to release.

 * `<pri>` is a new priority to assign to the job.

 * `<delay>` is an integer number of seconds to wait before putting the job in
   the ready queue. The job will be in the "delayed" state during this time.

##### `release` responses

The client expects one line of response, which may be:

 * `RELEASED\r\n` to indicate success.

 * `BURIED\r\n` if the server ran out of memory trying to grow the priority
   queue data structure.

 * `NOT_FOUND\r\n` if the job does not exist or is not reserved by the client.

#### `touch` command

The `touch` command allows a worker to request more time to work on a job. This is useful for jobs that potentially take a long time, but you still want the benefits of a TTR pulling a job away from an unresponsive worker.  A worker may periodically tell the server that it's still alive and processing a job (e.g. it may do this on `DEADLINE_SOON`).

The touch command looks like this:

```
touch <id>\r\n
```

##### `touch` options

* `<id>` is the ID of a job reserved by the current connection.

##### `touch` responses

There are two possible responses:

 * `TOUCHED\r\n` to indicate success.

 * `NOT_FOUND\r\n` if the job does not exist or is not reserved by the client.

#### `watch` command

The `watch` command adds the named tube to the watch list for the current connection. A reserve command will take a job from any of the tubes in the watch list. For each new connection, the watch list initially consists of one tube, named `default`.

```
watch <tube>\r\n
```

##### `watch` options

 * `<tube>` is a name at most 200 bytes. It specifies a tube to add to the watch list. If the tube doesn't exist, it will be created.

##### `watch` responses

The reply is:

  * `WATCHING <count>\r\n` `<count>` is the integer number of tubes currently in the watch list.

##### `ignore` command

The `ignore` command is for consumers. It removes the named tube from the watch list for the current connection.

```
ignore <tube>\r\n
```

##### `ignore` options

 * `<tube>` is a name at most 200 bytes. It specifies a tube to add to the watch list. If the tube doesn't exist, it will be created.

##### `ignore` command

The reply is one of:

 * `WATCHING <count>\r\n` to indicate success. `<count>` is the integer number of tubes currently in the watch list.

 * `NOT_IGNORED\r\n` if the client attempts to ignore the only tube in its watch list.






















