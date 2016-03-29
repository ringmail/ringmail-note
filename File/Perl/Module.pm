package Note::File::Perl::Module;
use strict;
use warnings;

use Moose;
use Pod::Autopod;
use Pod::Tree;
use Pod::Tree::Pod;
use IO::All;

use Note::Param;
use Note::File;

use base 'Note::File';

no warnings 'uninitialized';

sub generate_pod
{
	my ($obj, $param) = get_param(@_);
	my $fp = $obj->file();
	my $podfile = $fp;
	unless ($podfile =~ s/\.pm$/\.pod/)
	{
		die('Invalid extension for perl module');
	}
	my $ap = new Pod::Autopod(
		'readfile' => $fp,
	);
	return $ap->writeFile($podfile);
}

sub update_pod
{
	my ($obj, $param) = get_param(@_);
	my $fp = $obj->file();
	my $podfile = $fp;
	unless ($podfile =~ s/\.pm$/\.pod/)
	{
		die('Invalid extension for perl module');
	}
	unless (-e $podfile)
	{
		if ($param->{'generate'})
		{
			return $obj->generate_pod();
		}
		die(qq|POD file does not exist: '$podfile'|);
	}
	my $ap = new Pod::Autopod(
		'readfile' => $fp,
	);
	my $oldpod < io($podfile);
	my $newpod = $ap->getPod();
	my $oldtree = new Pod::Tree();
	$oldtree->load_string($oldpod);
	my $newtree = new Pod::Tree();
	$newtree->load_string($newpod);
	# read details
	my $olddet = $obj->get_section_details(
		'tree' => $oldtree,
	);
	my $newdet = $obj->get_section_details(
		'tree' => $newtree,
	);
	# merge methods
	my $oldmethods = (defined($olddet->{'parts'}->{'METHODS'})) ? $olddet->{'parts'}->{'METHODS'} : {};
	my $newmethods = (defined($newdet->{'parts'}->{'METHODS'})) ? $newdet->{'parts'}->{'METHODS'} : {};
	my %combined = ();
	foreach my $k (sort keys %$oldmethods)
	{
		# check to see if method removed
		if (exists $newmethods->{$k})
		{
			$combined{$k} = $oldmethods->{$k};
		}
	}
	foreach my $k (sort keys %$newmethods)
	{
		# check to see if method is in original
		unless (exists $oldmethods->{$k})
		{
			$combined{$k} = $newmethods->{$k};
		}
	}
	$olddet->{'parts'}->{'METHODS'} = \%combined;
	# assemble final sections
	my $resnodes = $obj->assemble_sections(
		'details' => $olddet,
	);
	my $root = $oldtree->get_root();
	$root->set_children($resnodes);
	# write output to POD file
	my $podwriter = new Pod::Tree::Pod($oldtree, $podfile);
	$podwriter->translate();
}

sub get_section_details
{
	my ($obj, $param) = get_param(@_);
	my $tree = $param->{'tree'};
	my $root = $tree->get_root();
	my $nodes = $root->get_children();
	my %parts = ();
	my %sections = ();
	my @path = ();
	my @order = ();
	foreach my $node (@$nodes)
	{
		my $type = $node->get_type();
		my $cmd = '';
		if ($type eq 'command')
		{
			$cmd = $node->get_command();
		}
		#::log("Node:: Type: $type Command: $cmd");
		# update path
		if ($cmd eq 'head1')
		{
			$path[0] = $node->get_text();
			$path[0] =~ s/(\r|\n)+$//mg;
			$path[1] = undef;
			push @order, $path[0];
			#::log("Section: $path[0]");
		}
		if ($path[0] eq 'METHODS')
		{
 			if ($cmd eq 'head2')
			{
				$path[1] = $node->get_text();
				$path[1] =~ s/(\r|\n)+$//mg;
				#::log("Subroutine: ". $path[1]);
			}
			elsif ($cmd eq 'cut')
			{
				$path[0] = 'END';
				$path[1] = undef;
				push @order, $path[0];
			}
		}
		# organize nodes
		if ($path[0] eq 'METHODS' && defined($path[1]))
		{
			$parts{$path[0]}->{$path[1]} ||= [];
			push @{$parts{$path[0]}->{$path[1]}}, $node;
		}
		else
		{
			$sections{$path[0]} ||= [];
			push @{$sections{$path[0]}}, $node;
		}
	}
	#::log(\%sections);
	return {
		'parts' => \%parts,
		'sections' => \%sections,
		'order' => \@order,
	};
}

sub assemble_sections
{
	my ($obj, $param) = get_param(@_);
	my $det = $param->{'details'};
	my $order = $det->{'order'};
	my $parts = $det->{'parts'};
	my $sections = $det->{'sections'};
	my @result = ();
	# iterate over each section in order
	foreach my $name (@$order)
	{
		my $items = $sections->{$name};
		# add the node to the result
		push @result, @$items;
		# add methods and other itemized nodes
		if (exists $parts->{$name})
		{
			foreach my $k (sort keys %{$parts->{$name}})
			{
				push @result, @{$parts->{$name}->{$k}};
			}
		}
	}
	return \@result;
}

1;

