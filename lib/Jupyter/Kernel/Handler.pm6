#= Lexical variable container for completion

unit class Jupyter::Kernel::Handler;
use Jupyter::Kernel::Comms;
use Log::Async;

has SetHash $.lexicals is rw;
has $.comms handles <comm-ids comm-names>
   = Jupyter::Kernel::Comms.new;

method BUILD {
    info "Completion Handler is created";
}

method register-comm($name, &callback --> Nil) {
    $.comms.add-comm-callback($name,&callback);
}

method add-lexicals(@list) {
    info "Adding lexicals: " ~ @list;
    $!lexicals{ |@list }»++;
}
