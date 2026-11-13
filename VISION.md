# Vision

torikomi exists because putting somebody else's file on your own disk is one
`curl` call in the happy case and a small piece of policy everywhere else: what
the file is called, what happens when a name is taken, what a half-written body
leaves behind, and what a stranger may make your server fetch. This is where that
argument goes next — from a service that sinks a file into a directory to one
whose directory is a library somebody can trust, address and audit.

## Where torikomi is today

torikomi is a GNU Artanis service on Guile Scheme, at 0.2.4. One work endpoint in
two shapes — `POST /sink-file` for the form, `POST /api/v1/sink-file` for JSON —
plus `GET /api/v1/version` and `GET /api/v1/health`. The form answers with the
same page carrying the sunk file's address or a sentence saying why the fetch
failed; the API answers with `sink-result->alist`, where a success carries
`file-name`, `url`, `new-url` and `bytes`, and a failure `error` and, when the
remote answered, `upstream-status`.

The interesting half is not the fetch. `sink-file` validates the URL against a
closed scheme list, restricts libcurl to those schemes for the request and every
redirect, takes the name from the reader's form, then `Content-Disposition`
(including RFC 5987 `filename*`), then the URL's last segment, then follows the
bytes for the extension, sanitises what it kept, reserves the name with `O_EXCL`,
writes to a temporary file and renames, retries the transient statuses with a
doubling delay, and bounds the body at `TORIKOMI_MAX_FILE_BYTES`. Every failure
is an ordinary answer: 400, 413, 502 with the upstream status, 500 only for a bug.

Four decisions now constrain what can be built without a rewrite:

- **The directory is flat and anonymous.** A file lands in
  `TORIKOMI_SINK_DIRECTORY` under a made-up name, with no record of where it came
  from, no grouping and no database — and the README's own word for the project
  is "collections and libraries", which the storage model does not express.
- **The body is fetched into memory.** `curl-easy-perform` returns a string, so
  `TORIKOMI_MAX_FILE_BYTES` is at once a policy limit and the memory ceiling.
- **Configuration is read once at module load**, from the environment, with an
  `env.scm` fallback and validation that ignores a value which does not mean
  anything — good to keep, and it leaves a per-request setting with no home.
- **The v1 answer shape is a promise.** `url` and `new-url` carry the same
  address because a client written against the first version must not have to
  change. Nothing in v1 may be removed, only added beside.

The page is a pure function of its arguments — translations, what the reader
typed, whether the last sink failed — so the unit suite renders it and reads it
as the markup a browser is handed, beside an end-to-end suite that stands up a
local HTTP server and sinks a real file into a temporary directory.

## The vision

1. **A sunk file can be accounted for.** For every file there is a record of the
   URL it came from, when, what the remote said it was, how large it is and what
   its bytes hash to — one that survives a rename, an upgrade and the removal of
   this software.
2. **The directory is a library, not a landing strip.** Collections are
   addressable things with stable public addresses, so a client can point at an
   archive rather than at a name it guessed.
3. **A sink is a budgeted request, not an unbounded favour.** Refusals are policy
   — a host the deployment will not fetch, a client over its quota, a scheme
   nobody asked for — rather than whichever limit was reached first.
4. **The test suite is the specification.** Every behaviour the manual claims is
   one a reader can run against a local server without a network, and a change
   that claims to be faster arrives with the number that shows it.
5. **Everything stays inspectable.** No format here needs a tool: the files are
   files, the index is text, and "what happened to that file" is `cat`, not a
   query.

## Features that are in scope and not built yet

- **A conflict strategy the caller chooses.** A collision is retried with a UUID
  suffix and nothing is ever overwritten — the safe answer, and the only one. The
  hard part is the third strategy, *replace only if the bytes are identical*,
  which needs a digest beside the file and an answer saying which happened.
- **Conversion on the way in** (AVIF, WebP, and whatever follows). The hard part
  is that this puts a decoder in the path of attacker-supplied bytes, in a
  service whose present trust boundary is a length: it wants a subprocess, a
  timeout and a memory cap, not a library call.
- **Bundling a collection as a tar or a zip.** The hard part is streaming an
  archive that was never fully on disk, and making the names inside it safe again
  — they came off the wire once and are no more trustworthy the second time.
- **Translation catalogues.** `#:i18n '(cookie "lang")` is wired into both routes
  and `sys/i18n/{locale,po,json,sxml}` holds nothing but `.gitkeep`. The hard
  part is that an error message is also an API field: the sentence a browser
  reads and the string a client branches on are the same string today.
- **A functional suite.** `test/functional/` is an empty directory. The hard part
  is testing the browser-facing half — the theme applied before first paint, the
  copy button — without an engine, or deciding the markup spec is that half.
- **A benchmark.** `test/benchmark/README` is the only file in it. The hard part
  is measuring a network-bound path honestly: the sink's own work must be
  separable from the transfer, or the number measures the loopback.
- **More than one file per request.** `sink-result->alist` is already the shape a
  list of results would use. The hard part is partial success: one item's failure
  not cancelling the rest, and a page that says which of twelve URLs failed
  without becoming a table nobody reads.

## New features that would be worth having

None of these is committed to; the first two are the ones worth arguing about.

- **A provenance index beside the files.** A JSONL or S-expression append-only
  log, one line per sink, keyed by the stored name: URL, final URL after
  redirects, timestamp, media type, byte count, SHA-256 — the cheapest possible
  version of "this is a library". The hard part is honesty about the write: index
  and file are two writes, and a crash between them must leave a state the reader
  can recognise.
- **Conditional re-sink.** Store the `ETag` and `Last-Modified` a remote sent; a
  second sink of the same URL asks `If-None-Match` first and answers "already
  have it, here it is". The hard part is finding the record for a URL when the
  name was chosen by a reader's form — the lookup the index solves.
- **Content-addressed storage as an option.** Naming files by digest gives
  deduplication for free and a collection that cannot be corrupted in place; it
  costs the readable names, so it belongs behind a setting.
- **A streaming write path.** libcurl's write callback into the reservation made
  with `O_EXCL`, so `TORIKOMI_MAX_FILE_BYTES` stops being a memory budget — the
  change that makes a 4 GiB video a reasonable request.
- **An address guard, a quota and a shared secret.** A sink is a proxy for the
  network the service sits on: a deployment with a private network and a
  reachable form lets anyone read what that network answers. Refusing loopback,
  link-local and private ranges by default — with a switch, because the tests
  need 127.0.0.1, and re-checked after every redirect — plus an optional bearer
  token and a byte budget per window, is the smallest policy worth having.

## Contributions that would move the needle

Roughly by value per hour.

1. **The provenance index.** An append-only writer, one new error case (index
   unwritable) and a spec that sinks two files and reads the lines back. It
   changes the project's character more than any feature five times its size.
2. **The address guard plus its test.** One predicate over the parsed host, with
   the redirect case tested — checking only the first hop is the classic way to
   leave the hole open. Highest ratio of safety gained to code written.
3. **The streaming write path, with a benchmark.** Bounded, local, and it unlocks
   every large-file argument afterwards; the benchmark must land with it or the
   claim is unverifiable.
4. **Translation catalogues and one non-English translation.** Unglamorous, and
   the repository was laid out for it from the start; the first catalogue is the
   hard one.
5. **The conflict strategies.** Well-scoped, testable against the existing local
   HTTP server, and the only README TODO a user feels immediately.
6. **The batch endpoint.** Worth doing after the index, because a batch's partial
   results are a listing problem before they are a transport problem.
7. **The functional suite, or its explicit removal.** Either a headless check of
   the first-paint theme and the copy button, or a sentence in the manual saying
   the markup spec is the contract.

## Compared to related projects

| Project | What it is | Where torikomi differs |
|---------|------------|------------------------|
| `curl` or `wget` in a cron job | The two commands a sink actually is, driven by a shell loop somebody wrote once | torikomi is the decisions that loop gets wrong, made once in a server: safe names, no overwrite, bounded size, retries, and a failure that is an ordinary HTTP answer rather than a non-zero exit nobody read |
| aria2 | A multi-protocol download engine with an RPC interface, sessions, resume and queues | torikomi is a web-facing ingest endpoint whose unit is one named file per request; it has no queue, no resume and no session, and its naming rules keep a directory coherent rather than finishing a transfer |
| yt-dlp | A media downloader with per-site extractors and elaborate output-template naming | torikomi fetches any `http(s)` resource, keeps no site-specific knowledge and treats the URL as the whole input; yt-dlp's notion of a video's identity is exactly what torikomi does not have |
| ArchiveBox | A self-hosted web archiver that turns a page into WARC, PDF, screenshot and DOM snapshots | ArchiveBox's unit is a page and its output a set of renditions; torikomi's unit is the file the URL names, with no browser engine, extractor or rendition pipeline |
| ocdownloader | A Nextcloud app that queues remote downloads into a folder through aria2 or curl | torikomi is standalone, single-purpose and API-first: no file-sync platform needed, and it answers a script as readily as a browser |
| imgproxy | On-the-fly image resizing and format conversion behind a signed URL | Not a sink at all — the useful contrast is that conversion-on-fetch is a whole service with its own signing and caching story, which is the scale of the "convert to AVIF" TODO if it is taken seriously |

What the others do that torikomi could still add: aria2's resume and its record
of what was in flight when it stopped — a resumable partial is a real gap;
yt-dlp's discipline of naming a resource by what it is rather than by its URL;
ArchiveBox's index and digest-based dedup, the best idea there for a directory
of downloads; and ocdownloader's queue, which a batch endpoint grows into.

Where torikomi is ahead: the answer shape — a failure is a status that means
something plus a sentence and, where it exists, the upstream status, while most
download tooling reports success and prints a message. Also the best-source
naming rule, the `O_EXCL` reservation with an atomic rename, and a closed scheme
list. Together they are why this is safe to leave running.

## In the long run

**Plain files and a plain index outlive the software.** An archive built with
torikomi in 2026 should still be readable without torikomi in 2036: no database
in the middle, a text index, and a sink directory that stays a directory
whatever else is added around it.

**The service becomes safe to expose.** Today a deployment is a form on a network
somebody else trusts. The multi-year version is a public ingest point: address
policy, quotas, tokens, an audit line per request, a documented refusal — the
unglamorous work that decides whether anyone but its author can run this.

**Artanis deserves a worked example of HTTP done properly.** torikomi is small
enough to read in an afternoon and fussy where a web service should be: status
codes, media types, escaping at the boundary, a failure that is a value rather
than a stack trace. If it stays that way its second contribution is as a
template: what someone clones when they want to serve from Guile and would rather
copy a correct answer than invent one.

The bet that would be wrong: that a sink is always one file from one URL. If
collections turn out to be what people use, the single-file record is a special
case of a manifest, and the design should leave room for that now.

## Closing

The next worthwhile version of torikomi is not a longer feature list. It is the
same endpoint with a record of what it did, a refusal that is policy, and claims
a benchmark can check.

*This document describes intent, not commitments: it is a direction to argue
with, and no line of it is a promise about a release.*
