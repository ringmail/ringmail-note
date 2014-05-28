package Note::RDF::Class;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Node;

use Note::Param;
use Note::RDF::Sparql;
use Note::RDF::NS 'ns_iri';

# instance data
has 'class' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'required' => 1,
);

has 'sparql' => (
	'is' => 'rw',
	'isa' => 'Note::RDF::Sparql',
);

sub get_super
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'class'};
	$class ||= $obj->class();
	my $gdb = $obj->sparql();
	my $sc = $gdb->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class')],
			[$class, ns_iri('rdfs', 'subClassOf'), '?inst'],
		],
	);
	my @sup = ();
	while (my $i = $sc->next())
	{
		push @sup, $i->{'inst'};
	}
	return \@sup;
}

sub get_super_all
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'class'};
	$class ||= $obj->class();
	my @sup = ();
	my %seen = ();
	my $iter;
	$iter = sub {
		my ($cl) = @_;
		my $lookup = $obj->get_super('class' => $cl);
		foreach my $n (@$lookup)
		{
			unless ($seen{$n->uri_value()}++)
			{
				push @sup, $n;
				$iter->($n);
			}
		}
	};
	$iter->($class);
	return \@sup;
}

sub get_subclass
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'class'};
	$class ||= $obj->class();
	my $gdb = $obj->sparql();
	my $sc = $gdb->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdfs', 'Class')],
			['?inst', ns_iri('rdfs', 'subClassOf'), $class],
		],
	);
	my @sub = ();
	while (my $i = $sc->next())
	{
		push @sub, $i->{'inst'};
	}
	return \@sub;
}

sub get_properties
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'class'};
	$class ||= $obj->class();
	my $gdb = $obj->sparql();
	my $attr = $gdb->build_sparql(
		'select' => ['distinct ?inst'],
		'where' => [
			['?inst', ns_iri('rdf', 'type'), ns_iri('rdf', 'Property')],
			['?inst', ns_iri('rdfs', 'domain'), $class],
		],
	);
	my @prop = ();
	while (my $i = $attr->next())
	{
		push @prop, $i->{'inst'};
	}
	return \@prop;
}

sub get_properties_all
{
	my ($obj, $param) = get_param(@_);
	my $class = $param->{'class'};
	$class ||= $obj->class();
	my $supercl = $obj->get_super_all('class' => $class);
	my $props = $obj->get_properties('class' => $class);
	my %seen = (map {$_->uri_value() => 1} @$props);
	if ($param->{'show_class'})
	{
		$props = [map {
			[$class, $_],
		} @$props];
	}
	foreach my $cl (@$supercl)
	{
		my $more = $obj->get_properties('class' => $cl);
		foreach my $m (@$more)
		{
			unless ($seen{$m->uri_value()}++)
			{
				if ($param->{'show_class'})
				{
					push @$props, [$cl, $m];
				}
				else
				{
					push @$props, $m;
				}
			}
		}
	}
	return $props;
}

1;

