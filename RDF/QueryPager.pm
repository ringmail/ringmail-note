package Note::RDF::QueryPager;
use strict;
use warnings;

use vars qw();

use Moose;

use Note::Param;
use Note::RDF::Sparql;
use Note::QueryPager;

use base ('Note::QueryPager');

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
	return $iter;
}

1;

