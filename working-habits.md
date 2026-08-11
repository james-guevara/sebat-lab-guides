# Working Habits (One Person's Opinions)

Nothing here is lab policy, and none of it is required. These are just habits I
drifted into after breaking things, written down in case any of them are useful.
Disagree freely — several are matters of taste, and I've marked which.

I don't follow all of these consistently myself. If you look at my project
directory you'll find plenty of loose one-off scripts of exactly the sort the
"organization" section advises against. Take that as evidence about how easy the
advice is to follow, not as a reason to dismiss it.

## Habits that came from breaking something

These are the ones I'd actually argue for. Each exists because something went
wrong once.

**Write scripts to a file and `scp` them. Don't pipe code through SSH.**

```bash
# this mangles quoting in ways that are genuinely hard to debug
ssh expanse 'python3 -c "print(f\"{x}\")"'

# this just works
scp analysis.py expanse:~/project/scripts/
ssh expanse 'python3 ~/project/scripts/analysis.py'
```

Nested quotes get eaten by two shells and an SSH layer. You also lose the ability
to re-run, diff, or version what you actually executed. A file costs ten seconds.

**Cancel jobs by explicit numeric ID, never by filter.**

```bash
scancel 53303934        # yes
scancel -u $USER        # no
scancel -n myjobname    # no
```

A filtered `scancel` once killed a 96-core job of mine that had been running for
hours and had nothing to do with what I was cleaning up. The filter matched more
than I pictured. Type the number.

**Use absolute paths, and say which machine you mean.** `~/data/` is ambiguous
across four filesystems and two hosts. `/expanse/projects/sebat1/j3guevar/data/`
is not. This matters much more once you're pasting commands to someone else, or
to an AI assistant that can't see your shell history.

**Don't put anything in `/tmp` on Expanse.** It isn't shared between login and
compute nodes, so a file your script writes there during a job is somewhere you
cannot find afterwards. Use home or project space.

**Dry-run before submitting.** `sbatch --test-only` validates account, partition,
and limits, tells you when the job would start, and queues nothing. Costs a
second, catches the `--partition=shared` mistake that would otherwise fail after
you've walked away.

## Claims and verification

This is the habit I most wish I'd adopted earlier, and the one I most often
still get wrong.

**Don't say something works until the output proving it is in front of you.**
"The job finished" and "I submitted the job" are different sentences. If you
haven't checked `sacct`, say "submitted, not verified" and give the command that
would check. This applies doubly when reporting to someone else, because they'll
build on your claim.

**Prove the logic on a slice that can fail in seconds.** Before a run that takes
an hour to falsify: one chromosome, 1,000 lines, one sample, `--dry-run`. Almost
every pipeline bug I've had would have surfaced on chr21 in thirty seconds. The
full run should be a formality, not an experiment.

**For long jobs, the deliverable is a job ID and a verification command**, not a
prediction of the result. Nobody can act on "it should finish around 3pm."

## Data tooling (mostly taste)

I reach for **Polars, DuckDB, and Parquet** over pandas and over anything
requiring a JVM. Partly this is real — no Spark cluster to stand up on an HPC
allocation, columnar formats that don't load what you didn't ask for, and Arrow
underneath so the tools compose without serialization boundaries. Partly it's
aesthetic: I find declarative, immutable pipelines a better fit for
bioinformatics than imperative mutation, and I like that a lazy query planner
can reorder work I'd otherwise hand-optimize.

I'd rather be honest that the second half is taste. If pandas is what you know
and your data fits in memory, that's a perfectly good answer and you should
ignore this section.

Worth knowing regardless: DuckDB ships as a single self-contained binary that
needs no environment, module, or root on Expanse. See
[filesize-expanse.md](filesize-expanse.md) for a worked example.

**`uv` instead of `pip`** for installs — it's dramatically faster and the
resolver is better. Low-stakes preference, easy to adopt, easy to ignore.

## Organizing a project (do as I say)

What I'd do if starting clean:

```
project/
  scripts/
    01_ingest.py          # numbered = the pipeline, in order
    02_annotate.py
    03_burden.py
    diagnostics/          # things that check the pipeline
    exploratory/          # things that were never meant to last
    README.md             # what to run, in what order, with what inputs
```

The numbering does the useful work: six months later you can tell what the
pipeline *is* without reading any code. The `exploratory/` directory matters
more than it looks, because the alternative isn't tidiness, it's twenty
`chk_thing2_final.py` files in the project root. Ask me how I know.

## Nextflow

Already covered properly in [nextflow-expanse.md](nextflow-expanse.md); the
short version of the three that cost me the most time:

- Override resources in `nextflow.config` with `withName:`, never by editing a
  module file — editing the module invalidates the cache and `-resume` restarts
  from the beginning.
- Never set `errorStrategy = 'ignore'` globally. You get silent zombie tasks and
  a pipeline that reports success having done nothing.
- Pass an explicit session UUID to `-resume` in chained-entry launchers. Bare
  `-resume` picks the most recent session, which is often the wrong one.

## Working with AI assistants on the cluster

Most of the above matters more, not less, when an agent is running commands:
absolute paths because it can't see your shell state, script files because
its heredocs get mangled the same way yours do, explicit job IDs because a
filtered `scancel` from an agent is exactly as destructive as one from you.
Ask for the verifying command alongside any claim that something worked.

See [claude-code-cluster.md](claude-code-cluster.md), particularly the section on
permission flags in batch jobs.

---

*If you disagree with something here, you're probably right about at least some
of it — open a PR and argue. I'd rather this file be contested than followed.*
