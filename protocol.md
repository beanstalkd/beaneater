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
| ``UNKNOWN_COMMAND\r\n` | The client sent a command that the server does not know. |


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

A process that wants to consume jobs from the queue uses:

1. `reserve`
2. `delete` 
3. `release` 
4. `bury`


##### `reserve` command

















