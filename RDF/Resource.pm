package Note::RDF::Resource;
use strict;
use warnings;
no warnings 'uninitialized';

use vars qw();

use Moose;
use Data::Dumper;
use RDF::Trine ('iri', 'statement', 'literal');
use RDF::Trine::Node;
use Note::Param;
use Note::RDF::NS ('ns_iri');
use Scalar::Util ('blessed', 'reftype');

no warnings qw(uninitialized);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Store',
	'required' => 1,
);

has 'subject' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'required' => 1,
);

has 'model_storage' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		return new RDF::Trine::Model($obj->storage());
	},
);

has 'context' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Node',
	'lazy' => 1,
	'default' => sub {
		return new RDF::Trine::Node::Nil();
	},
);

has 'model' => (
	'is' => 'rw',
	'isa' => 'RDF::Trine::Model',
	'lazy' => 1,
	'default' => sub {
		return new RDF::Trine::Model();
	},
);

has 'updated' => (
	'is' => 'rw',
	'isa' => 'Bool',
	'lazy' => 1,
	'default' => sub {
		return 0;
	},
);

has 'updates' => (
	'is' => 'rw',
	'isa' => 'Bool',
	'lazy' => 1,
	'default' => sub {
		return [];
	},
);

sub load
{
	my ($obj) = @_;
	my $rsrc = $obj->subject();
	my $ctxt = $obj->context();
	my $model = $obj->model_storage();
	my $propiter = $model->get_statements(
		$rsrc,
		undef,
		undef,
		$ctxt,
	);
	my $resmodel = $obj->model();
	$resmodel->add_iterator($propiter);
}

sub add
{
	my ($obj, $pred, $value, $dt) = @_;
	unless (blessed($pred) && $pred->isa('RDF::Trine::Node::Resource'))
	{
		die(qq|Invalid predicate for statement: '$pred'|);
	}
	unless (blessed($value) && $value->isa('RDF::Trine::Node'))
	{
		$value = literal($value, undef, $obj->get_datatype($dt));
	}
	my $mstore = $obj->model_storage();
	my $subject = $obj->subject();
	my $ctxt = $obj->context();
	$mstore->add_statement(statement($subject, $pred, $value), $ctxt);
}

sub get_datatype
{
	my ($obj, $dt) = @_;
	if (defined($dt) && ! blessed($dt) && reftype($dt) eq 'ARRAY')
	{
		$dt = ns_iri(@$dt);
	}
	elsif (defined($dt) && ! ref($dt) && $dt =~ /^xsd:(\w+)$/)
	{
		$dt = ns_iri('xsd', $1);
	}
	elsif (! defined($dt))
	{
		$dt = ns_iri('xsd', 'string');
	}
	return $dt;
}

sub remove
{
	my ($obj, $pred, $value, $dt) = @_;
	unless (blessed($pred) && $pred->isa('RDF::Trine::Node::Resource'))
	{
		die(qq|Invalid predicate for remove: '$pred'|);
	}
	unless (defined $value)
	{
		die(qq|Undefined value to remove|);
	}
	unless (blessed($value) && $value->isa('RDF::Trine::Node'))
	{
		$value = literal($value, undef, $obj->get_datatype($dt));
	}
	my $mstore = $obj->model_storage();
	my $subject = $obj->subject();
	my $ctxt = $obj->context();
	$mstore->remove_statements($subject, $pred, $value, $ctxt);
}

sub remove_all
{
	my ($obj, $pred) = @_;
	unless (blessed($pred) && $pred->isa('RDF::Trine::Node::Resource'))
	{
		die(qq|Invalid predicate for remove: '$pred'|);
	}
	my $mstore = $obj->model_storage();
	my $subject = $obj->subject();
	my $ctxt = $obj->context();
	my $iter = $mstore->get_statements($subject, $pred, undef, $ctxt);
	while (my $v = $iter->next())
	{
		$mstore->remove_statements($v->subject(), $v->predicate(), $v->object(), $ctxt);
	}
}

sub set
{
	my ($obj, $pred, $value, $dt) = @_;
	$obj->remove_all($pred);
	return $obj->add($pred, $value, $dt);
}

sub delete
{
	my ($obj) = @_;
	my $mstore = $obj->model_storage();
	my $subject = $obj->subject();
	my $ctxt = $obj->context();
	my $iter = $mstore->get_statements($subject, undef, undef, $ctxt);
	while (my $v = $iter->next())
	{
		$mstore->remove_statements($v->subject(), $v->predicate(), $v->object(), $ctxt);
	}
}

# in progress
sub update
{
	my ($obj, $upd) = @_;
	$obj->updated(1);
}

# in progress
sub flush
{
	my ($obj) = @_;
	if ($obj->updated())
	{
		# if updated, write changes
		foreach my $upd (@{$obj->updates()})
		{
		}
	}
}

1;

