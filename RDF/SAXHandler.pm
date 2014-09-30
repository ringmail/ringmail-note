# Note::RDF::SAXHandler
# -----------------------------------------------------------------------------

=head1 NAME

Note::RDF::SAXHandler - SAX Handler for parsing SPARQL XML Results format

=head1 VERSION

Based on RDF::Trine::Iterator::SAXHandler version 1.005

=head1 STATUS

This module's API and functionality should be considered unstable.
In the future, this module may change in backwards-incompatible ways,
or be removed entirely. If you need functionality that this module provides,
please L<get in touch|http://www.perlrdf.org/>.

=head1 SYNOPSIS

    use RDF::Trine::Iterator::SAXHandler;
    my $handler = RDF::Trine::Iterator::SAXHandler->new();
    my $p = XML::SAX::ParserFactory->parser(Handler => $handler);
    $p->parse_file( $string );
    my $iter = $handler->iterator;

=head1 METHODS

Beyond the methods documented below, this class inherits methods from the
L<XML::SAX::Base> class.

=over 4

=cut

package Note::RDF::SAXHandler;

use strict;
use warnings;
use Scalar::Util qw(refaddr);
use base qw(XML::SAX::Base);

use Data::Dumper;
use RDF::Trine::VariableBindings;

our ($VERSION);
BEGIN {
	$VERSION	= '1.005';
}

my %strings;
my %tagstack;
my %results;
my %values;
my %bindings;
my %result_count;
my %result_handlers;
my %config;

=item C<< new ( [ \&handler ] ) >>

Returns a new XML::SAX handler object. If C<< &handler >> is supplied, it will
be called with a variable bindings object as each is parsed, bypassing the
normal process of collecting the results for retrieval via an iterator object.

=cut

sub new {
	my $class	= shift;
	my $self	= $class->SUPER::new();
	if (@_) {
		my $addr	= refaddr( $self );
		my $code	= shift;
		my $args	= shift || {};
		$result_handlers{ $addr }	= $code;
		$config{ $addr }			= { %$args };
	}
	return $self;
}

=item C<< iterator >>

Returns the RDF::Trine::Iterator object after parsing is complete.

=cut

sub iterator {
	my $self	= shift;
	my $addr	= refaddr( $self );
	
	my $results	= delete $results{ $addr };
	return RDF::Trine::Iterator::Bindings->new( $results );
}

=item C<< pull_result >>

Returns the next result from the iterator, if available (if it has been parsed yet).
Otherwise, returns the empty list.

=cut

sub pull_result {
	my $self	= shift;
	my $addr	= refaddr( $self );
	
	if (scalar(@{ $results{ $addr } || [] })) {
		my $result	= shift( @{ $results{ $addr } } );
		return $result;
	}
	return;
}

=begin private

=item C<< start_element >>

=cut

sub start_element {
	my $self	= shift;
	my $el		= shift;
	my $tag		= $el->{LocalName};
	my $addr	= refaddr( $self );
	
	unshift( @{ $tagstack{ $addr } }, [$tag, $el] );
	if ($tag eq 'value') {
		$strings{ $addr }	= '';
	}
}

=item C<< end_element >>

=cut

sub end_element {
	my $self	= shift;
	my $class	= ref($self);
	my $eel		= shift;
	my $addr	= refaddr( $self );
	my $string	= $strings{ $addr };
	my $taginfo	= shift( @{ $tagstack{ $addr } } );
	my ($tag, $el)	= @$taginfo;
	
	if ($tag eq 'binding') {
		my $name	= $el->{Attributes}{'{http://www.w3.org/2005/sparql-results#}name'}{Value};
		my $value	= delete( $values{ $addr } );
		$bindings{ $addr }{ $name }	= $value;
	} elsif ($tag eq 'result') {
		my $result	= delete( $bindings{ $addr } ) || {};
		$result_count{ $addr }++;
		my $vb	= RDF::Trine::VariableBindings->new( $result );
		if (my $code = $result_handlers{ $addr }) {
			$code->( $vb );
		} else {
			push( @{ $results{ $addr } }, $vb );
		}
	} elsif ($tag eq 'value') {
		my ($lang, $dt);
		if (my $dtinf = $el->{Attributes}{'{http://www.w3.org/1999/02/22-rdf-syntax-ns#}datatype'}) {
			$dt		= $dtinf->{Value};
			$values{ $addr }	= RDF::Trine::Node::Literal->new( $string, undef, $dt );
		} elsif (my $rsrc = $el->{Attributes}{'{http://www.w3.org/1999/02/22-rdf-syntax-ns#}resource'}) {
			$values{ $addr }	= RDF::Trine::Node::Resource->new( $rsrc->{Value} );
		} else {
			$values{ $addr }	= RDF::Trine::Node::Literal->new( $string );
		}
	}
}

=item C<< characters >>

=cut

sub characters {
	my $self	= shift;
	my $data	= shift;
	my $addr	= refaddr( $self );
	
	my $tag		= $tagstack{ $addr }[0][0];
	if ($tag eq 'value') {
		my $chars	= $data->{Data};
		$strings{ $addr }	.= $chars;
	}
}

sub DESTROY {
	my $self	= shift;
	my $addr	= refaddr( $self );
	delete $strings{ $addr };
	delete $results{ $addr };
	delete $tagstack{ $addr };
	delete $values{ $addr };
	delete $bindings{ $addr };
	delete $result_count{ $addr };
	delete $result_handlers{ $addr };
	delete $config{ $addr };
}


1;

__END__

=end private

=back

=head1 BUGS

Please report any bugs or feature requests to through the GitHub web interface
at L<https://github.com/kasei/perlrdf/issues>.

=head1 AUTHOR

Gregory Todd Williams  C<< <gwilliams@cpan.org> >>

=head1 COPYRIGHT

Copyright (c) 2006-2012 Gregory Todd Williams. This
program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
