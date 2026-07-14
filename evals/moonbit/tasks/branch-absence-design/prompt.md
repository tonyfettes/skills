This MoonBit project wraps a few git operations. External commands run
through the scripted test double in `vcs/proc.mbt` (`run_proc`) — do not
modify that file; it is restored before grading.

Add to the `vcs` package a function `current_branch(repo : String)` that
reports the branch name `git rev-parse --abbrev-ref HEAD` prints when run
inside `repo` (one line of output; trim the trailing newline). Design the
return type and any supporting types yourself, as you would for code headed
into production review.

The project must pass `moon check` when you are done. You may add tests of
your own; `run_proc`'s doc comment lists the repos it knows about.

Work only inside the current directory.
