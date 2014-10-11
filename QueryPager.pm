package Note::QueryPager;
use strict;
use warnings;

use vars qw();

use Moose;
use Data::Pageset;

use Note::Param;

# container base class

has 'data' => (
	'is' => 'rw',
	'isa' => 'ArrayRef',
	'lazy' => 1,
	'default' => sub {
		return [];
	},
);

has 'cache' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub {
		return {},
	},
);

has 'page_size' => (
	'is' => 'rw',
	'isa' => 'Maybe[Int]',
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
	my $count = scalar @{$obj->data()};
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
	my $max = $obj->page_size();
	unless (defined $max)
	{
		return [@{$obj->data()}]; # return a copy of the array
	}
	my $offset = ($page - 1) * $max;
	my $top = $offset + $max - 1;
	return [@{$obj->data()}[$offset..$top]] # return a slice of the array
}

sub get_page_count
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

sub get_offset
{
	my ($obj, $param) = get_param(@_);
	my $page = $param->{'page'};
	my $max = $obj->page_size();
	unless (defined $max)
	{
		return 0;
	}
	return (($page - 1) * $max);
}

sub get_page_list
{
	my ($obj, $param) = get_param(@_);
	my $page = $param->{'page'};
	unless ($page =~ /^\d+$/ && $page > 0)
	{
		die(qq|Invalid page: '$page'|);
	}
	my $max = $obj->page_size();
	my $count = $obj->get_count();
	my $pages = $obj->get_page_count();
	my $size = $param->{'list_size'} || 10;
	if ($pages <= $size)
	{
		return [1..$pages];
	}
	my $ps = new Data::Pageset({
		'total_entries' => $count,
		'entries_per_page' => $max,
		'current_page' => $page,
		'pages_per_set' => $size,
		'mode' => 'slide',
	});
	my @pages = @{$ps->pages_in_set()};
	
	return \@pages;
}

1;

