unit class Jupyter::Kernel;

use JSON::Tiny;
use Log::Async;
use Net::ZMQ4::Constants;
use UUID;

use Jupyter::Kernel::Comms;
use Jupyter::Kernel::Magics;
use Jupyter::Kernel::Paths;
use Jupyter::Kernel::Sandbox;
use Jupyter::Kernel::Service;

has $.engine-id = ~UUID.new: :version(4);
has $.kernel-info = {
    protocol_version => '5.0',
    implementation => 'p6-jupyter-kernel',
    implementation_version => '0.0.11',
    language_info => {
        name => 'perl6',
        version => ~$*PERL.version,
        mimetype => 'text/plain',
        file_extension => '.p6',
    },
    banner => "Welcome to Perl 6 ({ $*PERL.compiler.name } { $*PERL.compiler.version }).",
}
has $.magics = Jupyter::Kernel::Magics.new;

has $.handler = Jupyter::Kernel::Handler.new;

method resources {
    return %?RESOURCES;
}

method run($spec-file!) {
    info 'starting jupyter kernel';

    my $spec = from-json($spec-file.IO.slurp);
    my $url = "$spec<transport>://$spec<ip>";
    my $key = $spec<key> or die "no key";

    # Get session
    my $session_count = 1;
    my $history-file = Jupyter::Kernel::Paths.history-file;
    if $history-file.e {
        my $old-session = ($history-file.lines[*-1] ~~ / ^ \[ (\d+) \, /);
        if $old-session {
            $session_count = $old-session[0].Int + 1;
        }
    }
    my $h_history = Jupyter::Kernel::Paths.history-file.open(:a, :!out-buffer);

    debug "read $spec-file";
    debug "listening on $url";

    sub svc($name, $type) {
        Jupyter::Kernel::Service.new( :$name, :socket-type($type),
                :port($spec{"{ $name }_port"}), :$key, :$url).setup;
    }

    my $ctl   = svc('control', ZMQ_ROUTER);
    my $shell = svc('shell',   ZMQ_ROUTER);
    my $iopub = svc('iopub',   ZMQ_PUB);
    my $hb    = svc('hb',      ZMQ_REP);

    start {
        $hb.start-heartbeat;
    }

    # Control
    start loop {
        my $msg = try $ctl.read-message;
        error "error reading data: $!" if $!;
        debug "ctl got a message: { $msg<header><msg_type> // $msg.perl }";
        given $msg<header><msg_type> {
            when 'shutdown_request' {
                my $restart = $msg<content><restart>;
                $restart = False;
                $ctl.send: 'shutdown_reply', { :$restart }
                exit;
            }
        }
    }

    # Shell
    my $execution_count = 1;
    my $sandbox = Jupyter::Kernel::Sandbox.new(:$.handler);

    my $promise = start {
    loop {
    try {
        my $msg = $shell.read-message;
        $iopub.parent = $msg;
        debug "shell got a message: { $msg<header><msg_type> }";
        given $msg<header><msg_type> {
            when 'kernel_info_request' {
                $shell.send: 'kernel_info_reply', $.kernel-info;
            }
            when 'execute_request' {
                $iopub.send: 'status', { :execution_state<busy> }
                my $code = ~ $msg<content><code>;
                # Save to history file
                start $h_history.say([$session_count, $execution_count, $code].perl ~ ',');
                my $status = 'ok';
                my $magic = $.magics.find-magic($code);
                my $result;
                $result = .preprocess($code) with $magic;
                $result //= $sandbox.eval($code, :store($execution_count));
                if $magic {
                    with $magic.postprocess(:$code,:$result) -> $new-result {
                        $result = $new-result;
                    }
                }
                my %extra;
                $status = 'error' with $result.exception;
                $iopub.send: 'execute_input', { :$code, :$execution_count, :metadata(Hash.new()) }
                if defined( $result.stdout ) {
                    if $result.stdout-mime-type eq 'text/plain' {
                        $iopub.send: 'stream', { :text( $result.stdout ), :name<stdout> }
                    } else {
                        $iopub.send: 'display_data', {
                            :data( $result.stdout-mime-type => $result.stdout ),
                            :metadata(Hash.new());
                        }
                    }
                }
                if defined ($result.stderr ) {
                    $iopub.send: 'stream', { :text( $result.stderr ), :name<stderr> }
                }
                unless $result.output-raw === Nil {
                    $iopub.send: 'execute_result',
                                { :$execution_count,
                                :data( $result.output-mime-type => $result.output ),
                                :metadata(Hash.new());
                                }
                }
                $iopub.send: 'status', { :execution_state<idle>, }
                my $content = { :$status, |%extra, :$execution_count,
                       user_variables => {}, payload => [], user_expressions => {} }
                $shell.send: 'execute_reply',
                    $content,
                    :metadata({
                        "dependencies_met" => True,
                        "engine" => $.engine-id,
                        :$status,
                        "started" => ~DateTime.new(now),
                    });
                $execution_count++;
            }
            when 'is_complete_request' {
                my $code = ~ $msg<content><code>;
                my $status = 'complete';
                if $code.ends-with('\\') {
                  $status = 'incomplete';
                }
                # invalid?
                debug "sending is_complete_reply: $status";
                $shell.send: 'is_complete_reply', { :$status }
            }
            when 'complete_request' {
                my $code = ~$msg<content><code>;
                my Int:D $cursor_pos = $msg<content><cursor_pos>;
                my (Int:D $cursor_start, Int:D $cursor_end, $completions)
                    = $sandbox.completions($code,$cursor_pos);
                if $completions {
                    $shell.send: 'complete_reply',
                          { matches => $completions,
                            :$cursor_end,
                            :$cursor_start,
                            metadata => {},
                            status => 'ok'
                    }
                } else {
                    $shell.send: 'complete_reply',
                          { :matches([]), :cursor_end($cursor_pos), :0cursor_start, metadata => {}, :status<ok> }
                }
            }
            when 'history_request' {
                use MONKEY-SEE-NO-EVAL;
                my $history = EVAL Jupyter::Kernel::Paths.history-file.slurp;
                $history = [] unless $history;
                $shell.send: 'history_reply', { :$history };
            }
            when 'comm_open' {
                my ($comm_id,$data,$name) = $msg<content><comm_id data target_name>;
                with $.handler.comms.add-comm(:id($comm_id), :$data, :$name) {
                    start react whenever .out -> $data {
                        debug "sending a message from $name";
                        $iopub.send: 'comm_msg', { :$comm_id, :$data }
                    }
                } else {
                    $iopub.send( 'comm_close', {} );
                }
            }
            when 'comm_msg' {
                my ($comm_id, $data) = $msg<content><comm_id data>;
                debug "comm_msg for $comm_id";
                $.handler.comms.send-to-comm(:id($comm_id),:$data);
            }
            default {
                warning "unimplemented message type: $_";
            }
        }
        CATCH {
            error "shell: $_";
            error "trace: { .backtrace.list.map: ~* }";
        }
    }}}
    await $promise;
}
