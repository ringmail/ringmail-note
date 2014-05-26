package Note::PSGI::Apache2;
use strict;
use warnings;

use Plack::Handler::Apache2;
use base qw(Plack::Handler::Apache2);

sub handler {
    my $class = __PACKAGE__;
    my $r     = shift;
    my $psgi  = $r->dir_config('psgi_app');
    $class->call_app($r, $class->load_app($psgi));
}

sub fixup_path
{
    my ($class, $r, $env) = @_;

    # $env->{PATH_INFO} is created from unparsed_uri so it is raw.
    my $path_info = $env->{PATH_INFO} || '';

    # Get argument of <Location> or <LocationMatch> directive
    # This may be string or regexp and we can't know either.
    my $location = $r->location;

    # Let's *guess* if we're in a LocationMatch directive
    if ($location eq '/') {
        # <Location /> could be handled as a 'root' case where we make
        # everything PATH_INFO and empty SCRIPT_NAME as in the PSGI spec
        $env->{SCRIPT_NAME} = '';
    } elsif ($path_info =~ s{^($location)/?}{/}) {
        $env->{SCRIPT_NAME} = $1 || '';
    } else {
        # Apache's <Location> is matched but here is not.
        # This is something wrong. We can only respect original.
		# --- Ok with Note ---
        #$r->server->log_error(
        #    "Your request path is '$path_info' and it doesn't match your Location(Match) '$location'. " .
        #    "This should be due to the configuration error. See perldoc Plack::Handler::Apache2 for details."
        #);
    }
    $env->{PATH_INFO}   = $path_info;
}

1;

