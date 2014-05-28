package Note::RDF::Schema;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use Note::Param;
use Note::RDF::NS ('ns_iri');
#use Scalar::Util 'blessed';

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'required' => 1,
);

has 'class' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node::Resource',
	'required' => 1,
);

has 'data' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'default' => sub { return {}; },
);

sub BUILD
{
	my ($obj) = @_;
	my $class = $obj->class();
	my $model = $obj->model();
	my $propiter = $model->get_statements(
		undef,
		ns_iri('rdfs', 'domain'),
		$class,
	);
	my $data = $obj->data();
	while (my $st = $propiter->next())
	{
		my $fld = $st->subject();
		my $pname = $fld->uri_value();
		my $rangeiter = $model->get_statements(
			$fld,
			ns_iri('rdfs', 'range'),
			undef,
		);
		my @range = ();
		while (my $st = $rangeiter->next())
		{
			my $robj = $st->object();
			unless ($robj->is_resource())
			{
				die(qq|Invalid rdfs:range for <$pname>|);
			}
			my $ruri = $robj->uri_value();
			push @range, $ruri;
		}
		unless (scalar @range)
		{
			die(qq|No rdfs:range for <$pname>|);
		}
		$data->{$pname} = \@range;
	}
}

sub get_super_classes
{
	my ($obj) = @_;
	my $class = $obj->class();
	my $model = $obj->model();
	my $superiter;
	my %seen = ();
	my @classes = ();
	$superiter = sub {
		my $nc = shift;
		my $iter = $model->get_statements(
			$nc,
			ns_iri('rdfs', 'subClassOf'),
			undef,
		);
		while (my $st = $iter->next())
		{
			my $x = $st->object();
			my $v = $x->uri_value();
			unless ($seen{$v})
			{
				push @classes, $v;
				$superiter->($x);
			}
		}
	};
	$superiter->($class);
	return \@classes;
}

1;

