package Note::RDF::Match;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Scalar::Util 'reftype';

use Note::Param;

has 'match' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'required' => 1,
);

has 'regex' => (
	'is' => 'rw',
	'isa' => 'ArrayRef',
	'default' => sub { return []; },
	'lazy' => 1,
);

has 'vals' => (
	'is' => 'rw',
	'isa' => 'ArrayRef',
	'default' => sub { return []; },
	'lazy' => 1,
);

sub BUILD
{
	my ($obj) = @_;
	my $baseurls = $obj->match();
    my $xmlregex = $obj->regex();
    my $xmlregex_ns = $obj->vals();
	my @ks = sort keys %$baseurls;
	if ($ks[0] eq '')
	{
		push @ks, shift @ks; # move the default to the end
	}
    foreach my $k (@ks)
    {
        my $qm = quotemeta($k);
        my $re = qr/^$qm/;
        push @$xmlregex, $re;
		if (ref($baseurls->{$k}) && reftype($baseurls->{$k}) eq 'HASH')
		{
        	push @$xmlregex_ns, new Note::RDF::Match(
				'match' => $baseurls->{$k},
			);
		}
		else
		{
        	push @$xmlregex_ns, $baseurls->{$k};
		}
    }
}

sub match_uri
{
	my ($obj, $param) = get_param(@_);
	my $pathref = $param->{'path'};
	my $item = $param->{'uri'};
	# allow recursive match
	my $baseurls = $obj->match();
    my $xmlregex = $obj->regex();
    my $xmlregex_ns = $obj->vals();
    foreach my $i (0..$#{$xmlregex})
    {
        my $re = $xmlregex->[$i];
        if ($item =~ /$re(.*$)/)
        {
            my $path = $1;
            if (ref($pathref) && $pathref =~ /SCALAR/)
            {
                $$pathref = $path;
            }
            my $val = $xmlregex_ns->[$i];
			if (ref($val) && $val->isa('Note::RDF::Match'))
			{
				return $val->match_uri($param);
			}
			return $val;
        }
    }
	return undef;
}

1;

