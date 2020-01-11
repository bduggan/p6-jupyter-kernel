Jupyter::Kernel for Raku
----------------
[![Build Status](https://travis-ci.org/bduggan/p6-jupyter-kernel.svg?branch=master)](https://travis-ci.org/bduggan/p6-jupyter-kernel)

[![Binder](https://mybinder.org/badge.svg)](https://mybinder.org/v2/gh/bduggan/p6-jupyter-kernel/master?filepath=eg%2Fhello-world.ipynb)

![autocomplete](https://user-images.githubusercontent.com/58956/29986517-c6a2020e-8f31-11e7-83da-086ad18bc662.gif)

This is a pure Raku implementation of a Raku kernel for Jupyter notebooks.

Jupyter notebooks provide a web-based (or console-based) REPL for running
code and serializing input and output.

REALLY QUICK START
-------------------

[Binder](https://mybinder.org/) provides a way to instantly launch a Docker
image and open a notebook.  Click `launch | binder` above
to start this kernel with a sample notebook.  (See below
for similar alternatives.)

QUICK START
-----------

### Installation
You'll need to install zmq.  Note that currently, version 4.1 is
recommended by Net::ZMQ (though 4.2 is installed by, e.g. homebrew).
If you run into stability issues, you may need to downgrade.

```
brew install zmq           # on OS/X
apt-get install libzmq-dev # on Ubuntu
```

You'll also want jupyter, for the front end:

```
pip install jupyter
```

Finally, install `Jupyter::Kernel`:

```
zef install Jupyter::Kernel
```

At the end of the above installation, you'll see the location
of the `bin/` directory which has `jupyter-kernel.raku`.  Make
sure that is in your `PATH`.

### Server Configuration
To generate a configuration directory, and to install a kernel
config file and icons into the default location:
```
jupyter-kernel.raku --generate-config
```
* Use `--location=XXX` to specify another location.
* Use `--force` to override an existing configuration.

### Client configuration
The jupyter documentation describes the client configuration.
To start, you can generate files for the notebook or
console clients like this:
```
jupyter notebook --generate-config
jupyter console --generate-config
```
Some suggested configuration changes for the console client:

   * set `kernel_is_complete_timeout` to a high number.  Otherwise,
     if the kernel takes more than 1 second to respond, then from
     then on, the console client uses internal (non-Perl6) heuristics
     to guess when a block of code is complete.

   * set `highlighting_style` to `vim`.  This avoids having dark blue
     on a black background in the console client.

### Logging
By default a log file `jupyter.log` will be written in the
current directory.  An option `--logfile=XXX` argument can be
added to the server configuration file to change this.

### Running
Start the web UI with:
```
jupyter-notebook
Then select new -> Raku
```

You can also use it in the console like this:
```
jupyter-console --kernel=raku
```

Or make a handy shell alias:

```
alias iraku='jupyter-console --kernel=raku'
```

### Features

* Autocompletion.  Typing `[tab]` in the client will send an autocomplete request.  Possible autocompletions are:

  * methods: after a `.` the invocant will be evaluated to find methods

  * set operators: after a ` (`, set operators (unicode and texas) will be shown (note the whitespace before the `(`)).

  * equality/inequality operators: after `=`, ` <`, or ` >`, related operators will be shown.

  * autocompleting ` *` or ` /` will give `×` or `÷` respectively.

  * autocompleting ` **` or a superscript will give you superscripts (for typing exponents).

  * the word 'atomic' autocompletes to the [atomic operators](https://docs.perl6.org/type/atomicint#Operators).  (Use `atomic-` or `atom` to get the subroutines with their ASCII names).

  * a colon followed by a sequence of word characters will autocomplete
    to characters whose unicode name contains that string.  Dashes are
    treated as spaces.
    e.g. :straw will find 🍓 ("STRAWBERRY") or 🥤 ("CUP WITH STRAW")  and :smiling-face-with-smiling-eye will find 😊 ("SMILING FACE WITH SMILING EYES")

* All cells are evaluated in item context.  Outputs are then saved to an array
named `$Out`.  You can read from this directly or:

  * via the subroutine `Out` (e.g. `Out[3]`)

  * via an underscore and the output number (e.g. `_3`)

  * for the most recent output: via a plain underscore (`_`).

* Magics.  There is some support for jupyter "magics".  If the first line
of a code cell starts with `#%` or `%%`, it may be interpreted as a directive
by the kernel.  See EXAMPLES.  The following magics are supported:

  * `#% javascript`: return the code as javascript to the browser

  * `#% html`: return the output as html

  * `#% latex`: return the output as LaTeX.  Use `latex(equation)` to wrap
   the output in `\begin{equation}` and `\end{equation}`.  (Or replace
   "`equation`" with another string to use something else.)

  * `#% html > latex`: The above two can be combined to render, for instance,
  the output cell as HTML, but stdout as LaTeX.

  * `%% bash`: Interpret the cell as bash.  stdout becomes the contents of
  the next cell.  Behaves like Perl 6's built-in `shell`.

  * `%% run FILENAME`: Prepend the contents of FILENAME to the
  contents of the current cell (if any) before execution.
  Note this is different from the built-in `EVALFILE` in that
  if any lexical variables, subroutines, etc. are declared in FILENAME,
  they will become available in the notebook execution context.

* Comms.  Comms allow for asynchronous communication between a notebook
and the kernel.  For an example of using comms, see [this notebook](eg/comms.ipynb)

### Usage notes

* In the console, pressing return will execute the code in a cell.  If you want
a cell to span several lines, put a `\` at the end of the line, like so:

```
In [1]: 42
Out[1]: 42

In [2]: 42 +
Out[2]: Missing required term after infix

In [3]: 42 + \
      : 10 + \
      : 3 + \
      : 12
Out[3]: 67
```

Docker
-------

[This blog post](https://sumankhanal.netlify.com/post/raku_notebook/) provides
a tutorial for running this kernel with Docker.  [This one](https://sumdoc.wordpress.com/2018/01/04/using-perl-6-notebooks-in-binder/) describes using [Binder](https://mybinder.org/).

EXAMPLES
--------

The [eg/](eg/) directory of this repository has some
example notebooks:

*  [Hello, world](eg/hello-world.ipynb).

*  [Generating an SVG](eg/svg.ipynb).

*  [Some unicodey math examples](http://nbviewer.jupyter.org/github/bduggan/p6-jupyter-kernel/blob/master/eg/math.ipynb)

*  [magics](http://nbviewer.jupyter.org/github/bduggan/p6-jupyter-kernel/blob/master/eg/magics.ipynb)

SEE ALSO
--------
* [Docker image for Perl 6](https://hub.docker.com/r/sumankhanal/raku-notebook/)

* [iperl6kernel](https://github.com/timo/iperl6kernel)

KNOWN ISSUES
---------
* Definitions of operators are not preserved (see [bug 131530](https://rt.perl.org/Public/Bug/Display.html?id=131530)).

* Newly declared methods might not be available in autocompletion unless SPESH is disabled (see tests in [this PR](https://github.com/bduggan/p6-jupyter-kernel/pull/11)).

THANKS
--------
Suman Khanal

Matt Oates

Timo Paulssen
