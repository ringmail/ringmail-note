package Note::RDF::Container;
use strict;
use warnings;

use vars qw();

use Moose;

use Note::Param;
use Note::RDF::Sparql;
use Note::Container;

use base ('Note::Container');

# SPARQL paged query container

has 'query' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'required' => 1,
);

has 'count_query' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'required' => 1,
);

has 'sparql' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
	'required' => 1,
);

# overload this
sub get_count
{
	my ($obj) = @_;
	my $cache = $obj->cache();
	if (defined $cache->{'count'})
	{
		return $cache->{'count'};
	}
	my $sp = $obj->sparql();
	my $query = $obj->count_query();
	my $sparql = $query->{'sparql'};
	my $iter = undef;
	if (defined $sparql)
	{
		$iter = $sp->query('sparql' => $sparql);
	}
	else
	{
		$iter = $sp->build_sparql($query);
	}
	my $count = $iter->next()->{'count'}->literal_value();
	$cache->{'count'} = $count;
	return $count;
}

# overload this
sub get_page
{
	my ($obj, $param) = get_param(@_);
	my $page = $param->{'page'};
	unless ($page =~ /^\d+$/ && $page > 0)
	{
		die(qq|Invalid page: '$page'|);
	}
	my $sp = $obj->sparql();
	my $query = $obj->query();
	my $max = $obj->page_size();
	if (defined $max)
	{
		my $offset = ($page - 1) * $max;
		$query->{'offset'} = $offset;
		$query->{'limit'} = $max;
	}
	my $iter = $sp->build_sparql($query);
	my @res = ();
	while (my $r = $iter->next())
	{
		push @res, $r;
	}
	return \@res;
}

sub get_count_pages
{
	my ($obj) = @_;
	my $count = $obj->get_count();
	my $max = $obj->page_size();
	unless (defined $max)
	{
		return 1; # 1 page for all items
	}
	my $md = $count % $max;
	my $i = ($count - $md) / $max;
	return $i + (($md > 0) ? 1 : 0);
}

1;
