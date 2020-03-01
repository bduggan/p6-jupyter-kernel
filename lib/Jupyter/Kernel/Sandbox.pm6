#!perl6

use Log::Async;
use Jupyter::Kernel::Sandbox::Autocomplete;
use Jupyter::Kernel::Response;
use Jupyter::Kernel::Handler;
use nqp;

%*ENV<RAKUDO_LINE_EDITOR> = 'none';
%*ENV<RAKUDO_DISABLE_MULTILINE> = 0;

my class Result does Jupyter::Kernel::Response {
    has Str $.output;
    has $.output-raw is default(Nil);
    has $.exception;
    has Bool $.incomplete;
    has $.stdout;
    has $.stderr;
    method !mime-type($str) {
        return do given $str {
            when /:i ^ '<svg' / {
                'image/svg+xml';
            }
            default { 'text/plain' }
        }
    }
    method stdout-mime-type {
        return self!mime-type($.stdout // '');
    }
    method output-mime-type {
        return self!mime-type($.output // '');
    }
}

class Jupyter::Kernel::Sandbox is export {
    has $.save_ctx;
    has $.compiler;
    has $.repl;
    has Jupyter::Kernel::Sandbox::Autocomplete $.completer;
    has $.handler;

    method TWEAK (:$!handler) {
        $!handler = Jupyter::Kernel::Handler.new unless $.handler;
        $!compiler := nqp::getcomp("Raku") || nqp::getcomp('perl6');
        $!repl = REPL.new($!compiler, {});
        $!completer = Jupyter::Kernel::Sandbox::Autocomplete.new(:$.handler);
        self.eval(q:to/INIT/);
            my $Out = [];
            sub Out { $Out };
            my \_ = do {
                state $last;
                Proxy.new( FETCH => method () { $last },
                           STORE => method ($x) { $last = $x } );
            }
        INIT
    }

    method eval(Str $code, Bool :$no-persist, Int :$store) {
        my $stdout;
        my $stderr;
        my $*CTXSAVE = $!repl;
        my $*MAIN_CTX;
        my $*ERR = class {
            method print(*@args) {
                $stderr ~= @args.join;
                return True but role { method __hide { True } }
            }
            method say(*@args) {
                self.print(@args.map: * ~ "\n");
            }
            method flush { }
        }
        my $*OUT = class {
            method print(*@args) {
                $stdout ~= @args.join;
                return True but role { method __hide { True } }
            }
            method say(*@args) {
                self.print(@args.map: * ~ "\n");
            }
            method flush { }
        }
        # without setting $PROCESS:: variants, output from Test.pm6
        # is not visible in the notebook.
        temp $PROCESS::OUT = $*OUT;
        temp $PROCESS::ERR = $*ERR;
        my $exception;
        my $eval-code = $code;
        my $*JUPYTER = $.handler;
        if $store {
            $eval-code = qq:to/DONE/
                my \\_$store = \$(
                    $code
                );
                \$*JUPYTER.add-lexicals( MY::.keys );
                \$Out[$store] := _$store;
                _ = _$store;
                DONE
        }
        if $no-persist {
            # use a temporary package
            $eval-code = qq:to/DONE/;
            my \$out is default(Nil);
            package JupTemp \{
                \$out = $( $code )
            \}
            for (JupTemp::).keys \{
                (JupTemp::)\{\$_\}:delete;
            \}
            \$out;
            DONE
        }

        my $output is default(Nil);
        my $gist;
        try {
            $output = $!repl.repl-eval(
                $eval-code,
                $exception,
                :outer_ctx($!save_ctx),
                :interactive(1)
            );
            $gist = $output.gist;
            CATCH {
                default {
                    $exception = $_;
                }
            }
        }
        given $output {
            $_ = Nil if .?__hide;
            $_ = Nil if $_ ~~ List and .elems and .[*-1].?__hide;
            $_ = Nil if $_ === Any;
        }

        if $*MAIN_CTX and !$no-persist {
            $!save_ctx := $*MAIN_CTX;
        }

        with $exception {
            $output = ~$_;
            $gist = $output;
        }
        my $incomplete = so $!repl.input-incomplete($output);
        my $result = Result.new:
            :output($gist),
            :output-raw($output),
            :$stdout,
            :$stderr,
            :$exception,
            :$incomplete;

        $result;
    }

    method completions($str, $cursor-pos = $str.chars ) {
        return self.completer.complete($str,$cursor-pos,self);
    }
}
