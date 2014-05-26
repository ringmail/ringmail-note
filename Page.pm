package Note::Page;
use strict;
use warnings;
no warnings qw(uninitialized);

use Moose;
use URI::Escape qw(uri_escape_utf8);
use HTML::Entities qw(encode_entities decode_entities);
use Scalar::Util qw(reftype);

use Note::Param;
use Note::XML qw(xml);
use Note::Session;
use Note::App;

extends 'Note::File::JSON';

has 'app' => (
	'is' => 'rw',
	'isa' => 'Note::App',
);

has 'storage' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		return $obj->app()->storage();
	},
);

has 'root' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'remote_ip' => (
	'is' => 'rw',
	'isa' => 'Str',
);

has 'hostname' => (
	'is' => 'rw',
	'isa' => 'Str',
	'required' => 1,
);

has 'port' => (
	'is' => 'rw',
	'isa' => 'Int',
);

has 'template' => (
	'is' => 'rw',
	'isa' => 'Note::Template',
);

has 'request' => (
	'is' => 'rw',
	'isa' => 'Plack::Request',
);

has 'response' => (
	'is' => 'rw',
	'isa' => 'Plack::Response',
);

has 'path' => (
	'is' => 'rw',
	'isa' => 'ArrayRef',
);

has 'form' => (
	'is' => 'rw',
	'isa' => 'HashRef',
);

has 'env' => (
	'is' => 'rw',
	'isa' => 'HashRef',
);

has 'body' => (
	'is' => 'rw',
	'isa' => 'ScalarRef',
);

has 'content' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub {
		my $obj = shift;
		my $data = $obj->data();
		$data->{'content'} ||= {};
		$data->{'content'}->{'page'} ||= $obj;
		return $data->{'content'};
	},
);

has 'value' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'command_index' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has 'command_button' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub { return {}; },
);

has '_session' => (
	'is' => 'rw',
	'isa' => 'Note::Session',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $appcfg = $obj->app()->config()->{'session'};
		my %sesscfg = (
			'page' => $obj,
			'type' => $appcfg->{'type'},
		);
		if ($appcfg->{'type'} eq 'sql')
		{
			$sesscfg{'database'} = $obj->storage()->{$appcfg->{'sql_database'}};
		}
		elsif ($appcfg->{'type'} eq 'file')
		{
			$sesscfg{'path'} = $appcfg->{'path'};
		}
		return new Note::Session(\%sesscfg);
	},
);

has 'session' => (
	'is' => 'rw',
	'isa' => 'HashRef',
	'lazy' => 1,
	'default' => sub {
		my ($obj) = @_;
		my $data = $obj->_session()->get();
		$data ||= {};
		return $data;
	},
);

sub session_write
{
	my ($obj) = shift;
	my $sd = $obj->session();
	$obj->_session()->set($sd);
}

sub param
{
	shift(@_);
	return Note::Param::get_param(@_);
}

# run init scripts
sub init
{
	my ($obj) = shift;
	# load session
	$obj->session();
	my $data = $obj->data();
	if (exists($data->{'init'}) && reftype($data->{'init'}) eq 'ARRAY')
	{
		my $ok;
		foreach my $i (@{$data->{'init'}})
		{
			my $warning = undef;
			eval {
				$SIG{__WARN__} = sub {
					$warning = $_[0];
					return;
				};
				$ok = $obj->$i(@_);
			};
			if (defined $warning)
			{
				::_errorlog(qq|Warning for init method: '$i'|, $warning);
			}
			if ($@) # handle error
			{
				my $err = $@;
				::_errorlog(qq|Init method error: '$i'|, $@);
				die(qq|Init method error: '$i'|);
			}
			return 0 unless ($ok);
		}
	}
	return 1;
}

# run a command, if there is one
sub run_command
{
	my ($obj, $param) = $_[0]->param(@_);
	my $cmd = $obj->_form_command();
	if (defined $cmd)
	{
		my $cmdname = $cmd->{'command'};
		my $objdata = $obj->data();
		unless (
			exists($objdata->{'command'}) &&
			(reftype($objdata->{'command'}) eq 'HASH') &&
			exists($objdata->{'command'}->{$cmdname})
		) {
			die(qq|Unknown command: '$cmdname'|);
		}
		my $cmdmethod = $objdata->{'command'}->{$cmdname};
		my $args = $cmd->{'args'};
		my $data = $cmd->{'data'};
		my $warning = undef;
		eval {
			$SIG{__WARN__} = sub {
				$warning = $_[0];
				return;
			};
			$obj->$cmdmethod($data, $args, @_);
		};
		if (defined $warning)
		{
			::_errorlog(qq|Warning for command method: '$cmdname'|, $warning);
		}
		if ($@) # handle error
		{
			my $err = $@;
			$err =~ s/^/\t/mg;
			#::_errorlog(qq|Command error: '$cmdname'|, $err);
			die("Command error: '$cmdname':\n$err");
		}
	}
}

# build the page
sub load
{
	my ($obj, $param) = $_[0]->param(@_);
	$obj->response()->content_type('text/html; charset=utf-8');
	my $data = $obj->data();
	if (defined $data)
	{
		if (defined $data->{'template'})
		{
			my $tmp = $obj->template();
			if (defined $tmp)
			{
				my $content = $obj->content();
				return $tmp->apply($data->{'template'}, $content);
			}
		}
	}
}

sub redirect
{
	my ($obj, $url) = @_;
	$obj->response()->redirect($url, 302);
}

sub _form_command
{
	my ($obj) = @_;
	my $form = $obj->form();
	my @ks = keys %$form;
	my @do_keys = grep /^do-\d+_(\d+|\d+\.x)$/, @ks;
	my $cmdname = undef;
	my @cmdargs = ();
	my %cmddata = ();
	if ($#do_keys == 0)
	{
		$do_keys[0] =~ s/\.x$//;
		$do_keys[0] =~ /^do-(\d+)_(\d+)$/;
		my $cmdbutton = $1;
		my $cmdnum = $2;
		my $cmdkey = 'cmd-'. $cmdbutton. '_'. $cmdnum;
		$cmdname = $form->{$cmdkey};
		my $zero = "\0";
		if ($cmdname =~ /$zero/)
		{
			$cmdname = s/$zero.*//;
		}
		my @ar = ();
		foreach my $k (@ks)
		{
			if ($k =~ /^(f_)?d$cmdnum\-(.*)$/)
			{
				$cmddata{$2} = $form->{$k};
			}
			elsif ($k =~ /^(\w+)-$cmdbutton\_$cmdnum/)
			{
				my $t = $1;
				if ($t =~ /^a/)
				{
					push @ar, $t;
				}
			}
		}
		foreach my $i (0..$#ar)
		{
			my $k = "a$i-$cmdbutton\_$cmdnum";
			if (exists $form->{$k})
			{
				my $v = $form->{$k};
				if ($v =~ /$zero/)
				{
					$v = s/$zero.*//;
				}
				push @cmdargs, $v;
			}
			else
			{
				last;
			}
		}
	}
	elsif ($#do_keys > 0)
	{
		die 'More than one command specified';
	}
	return undef unless (defined $cmdname);
	return {
		'command' => $cmdname,
		'args' => \@cmdargs,
		'data' => \%cmddata,
	};
}

sub _command_index
{
	my ($obj, $cmd) = @_;
	unless (defined $cmd)
	{
		die('Undefined command');
	}
	if ($cmd =~ /[^A-Za-z0-9\.\-\_\+]/)
	{
		die("Invalid command name: $cmd");
	}
	elsif (length($cmd) == 0)
	{
		die('Empty command name');
	}
	my $cmds = $obj->command_index();
	if (exists $cmds->{$cmd})
	{
		return $cmds->{$cmd};
	}
	else
	{
		my @k = keys %$cmds;
		my $n = scalar(@k) + 1;
		$cmds->{$cmd} = $n;
		return $n;
	}
}

sub _command_build
{
	my ($obj, $cmdname, $query, $button, $cmdargs) = @_;
	my $cmdnum = $obj->_command_index($cmdname);
	unless (ref($cmdargs) && $cmdargs =~ /ARRAY/)
	{
		$cmdargs = [];
	}
	my $cmdbutton = 1;
	if ($button)
	{
		$cmdbutton = ++$obj->command_button()->{$cmdname};
	}
	unless (ref($cmdargs) and $cmdargs =~ /ARRAY/)
	{
		$cmdargs = [];
	}
	my $args = {};
	foreach my $i (0..$#{$cmdargs})
	{
		$args->{"a$i\-$cmdbutton\_$cmdnum"} = $cmdargs->[$i];
	}
	$query->{"cmd-$cmdbutton\_$cmdnum"} = $cmdname;
	foreach my $k (keys %$args)
	{
		$query->{$k} = $args->{$k};
	}
	return [$cmdnum, $cmdbutton];
}

sub url
{
	my ($obj, $param) = get_param(@_);
	my $req = $obj->request();
	my $env = $req->env();
	unless (defined $param->{'proto'})
	{
		$param->{'proto'} = 'http';
		if ($req->scheme() eq 'https')
		{
			$param->{'proto'} = 'https';
		}
    }
    unless (defined $param->{'host'})
    {
		$param->{'host'} = $env->{'HTTP_HOST'};
		$param->{'host'} =~ s/\:.*$//;
    }
	if (
		(! defined $param->{'port'}) && (
			(($param->{'proto'} eq 'http') && $env->{'SERVER_PORT'} != 80) ||
			(($param->{'proto'} eq 'https') && $env->{'SERVER_PORT'} != 443)
		)
	) {
		$param->{'port'} = $env->{'SERVER_PORT'};
	}
	if (defined $param->{'port'})
	{
		$param->{'host'} .= ':'. $param->{'port'};
	}
    unless (defined $param->{'path'})
    {
		my $path = $req->request_uri();
		$path =~ s/\?.*$//;
        $param->{'path'} = $path;
    }
    $param->{'path'} =~ s/^\///;
    my $url = $param->{'proto'}. '://'. $param->{'host'}. '/'. $param->{'path'};
	my $query = {};
    if (ref $param->{'query'} && $param->{'query'} =~ /HASH/)
    {
		$query = $param->{'query'};
	}
	if (defined $param->{'command'})
	{
		my $cmdsetup = $obj->_command_build($param->{'command'}, $query, 0, $param->{'args'});
		my $cmdnum = $cmdsetup->[0];
		$query->{"do-1_$cmdnum"} = 1;
	}
	my @queryparts = ();
    foreach my $k (keys %$query)
    {
		next unless (defined $query->{$k});
        if (ref $query->{$k} and $query->{$k} =~ /ARRAY/)
        {
            foreach my $e (@{$query->{$k}})
            {
                push @queryparts, uri_escape_utf8($k). '='. uri_escape_utf8($e);
            }
        }
		else
        {
			push @queryparts, uri_escape_utf8($k). '='. uri_escape_utf8($query->{$k});
        }
    }
    if ($#queryparts > -1)
	{
		# Original:
		#my $amp = '&amp;';
		#if (exists $param->{'amp'} && ! $param->{'amp'})
		#{
		#	$amp = '&';
		#}

		my $amp = '&';
		if ($param->{'amp'})
		{
			$amp = '&amp;';
		}
		$url .= '?'. join($amp, @queryparts);
	}
	if (defined $param->{'name'})
	{
		$url .= '#'. $param->{'name'};
	}
    return $url;
}

sub link
{
	my ($obj, $param) = get_param(@_);
	my $opts = {};
	if (ref($param->{'opts'}) && $param->{'opts'} =~ /HASH/)
	{
		$opts = $param->{'opts'};
	}
	my %urlparam = ();
	foreach my $i (qw/query name path host proto command args/)
	{
		if (exists $param->{$i})
		{
			$urlparam{$i} = $param->{$i};
		}
	}
	my $result = xml(
		'a', [{
			'href' => $obj->url(\%urlparam),
			%$opts,
		},
			0, $param->{'text'},
		],
	);
	return $result;
}

sub field
{
	my ($obj, $param) = get_param(@_);
	my $name = $param->{'name'};
	unless (length($name))
	{
		die 'Empty field name';
	}
	if ($name =~ /[^A-Za-z0-9\-\_\+\.]/)
	{
		die "Invalid field name: $name";
	}
	my $n;
	if (exists $param->{'command'})
	{
		my $cmdnum = $obj->_command_index($param->{'command'});
		$n = "d$cmdnum-$name";
	}
	else
	{
		$n = $name;
	}
	my $type = lc($param->{'type'});
	my %opts = ();
	if (exists($param->{'opts'}) and reftype($param->{'opts'}))
	{
		%opts = %{$param->{'opts'}};
	}
	if ($type eq 'textarea')
	{
		return xml(
			'textarea', [{
				'name' => $n,
				%opts,
			},
				0, $param->{'value'},
			],
		);
	}
	elsif ($type eq 'text')
	{
		return xml(
			'input', [{
				'type' => 'text',
				'value' => $param->{'value'},
				'name' => $n,
				%opts,
			}],
		);
	}
	elsif ($type eq 'password')
	{
		return xml(
			'input', [{
				'type' => 'password',
				'value' => $param->{'value'},
				'name' => $n,
				%opts,
			}],
		);
	}
	elsif ($type eq 'radio')
	{
		my %checked = ();
		if ($param->{'checked'})
		{
			$checked{'checked'} = 'on';
		}
		return xml(
			'input', [{
				'type' => 'radio',
				'name' => $n,
				'value' => $param->{'value'},
				%checked,
				%opts,
			}],
		);
	}
	elsif ($type eq 'checkbox')
	{
		my %checked = ();
		if ($param->{'checked'})
		{
			$checked{'checked'} = 'on';
		}
		return xml(
			'input', [{
				'type' => 'checkbox',
				'name' => $n,
				%checked,
				%opts,
			}],
		);
	}
	elsif ($type eq 'select')
	{
		$param->{'size'} = 1 unless ($param->{'size'});
		my $options = '';
		foreach my $sel (@{$param->{'select'}})
		{
			if (ref $sel and $sel =~ /ARRAY/)
			{
				my $item = $sel->[0];
				if (ref($item) and $item =~ /SCALAR/)
				{
					$options .= xml('optgroup', [{'label' => $$item}, 0, ' ']);
				}
				else
				{
					my %optargs = (
						'value' => $sel->[1],
					);
					my $on = 0;
					if (defined($param->{'selected'}))
					{
						if ($param->{'selected'} eq $sel->[1])
						{
							$on = 1;
						}
					}
					if ($sel->[2] || $on)
					{
						$optargs{'selected'} = 'on';
					}
					$options .= xml('option', [\%optargs, 0, $item]);
				}
			}
		}
		return xml(
			'select', [{
				'size' => $param->{'size'},
				'name' => $n,
				%opts,
			},
				0, $options,
			],
		);
	}
	elsif ($type eq 'file')
	{
		return xml(
			'input', [{
				'type' => 'file',
				'name' => 'f_'. $n,
				%opts,
			}],
		);
	}
	elsif ($type eq 'hidden')
	{
		return xml(
			'input', [{
				'type' => 'hidden',
				'name' => $n,
				'value' => $param->{'value'},
				%opts,
			}],
		);
	}
	else
	{
		die(qq|Invalid field type: '$param->{'type'}'|);
	}
	return undef;
}

# params:
#  command
#  args
#  opts
#  contents
#  tag
#  type
#  image
sub button
{
	my ($obj, $param) = get_param(@_);
	my $extra = {};
	my $cmdsetup = $obj->_command_build($param->{'command'}, $extra, 1, $param->{'args'});
	my $cmdnum = $cmdsetup->[0];
	my $cmdbutton = $cmdsetup->[1];
	my $opts = {};
	if (ref($param->{'opts'}) && $param->{'opts'} =~ /HASH/)
	{
		$opts = $param->{'opts'};
	}
	my $res = $obj->hidden($extra);
	my @contents = ();
	if (defined $param->{'contents'})
	{
		push @contents, 0, $param->{'contents'};
	}
	my $tag = $param->{'tag'} || 'button';
	my $type = $param->{'type'} || 'submit';
	if (defined $param->{'image'})
	{
		$res .= xml(
			$tag, [{
				'type' => 'image',
				'name' => "do-$cmdbutton\_$cmdnum",
				'src' => $param->{'image'},
				'border' => (exists $param->{'border'}) ? $param->{'border'} : 0,
				%$opts,
			}, @contents],
		);
	}
	else
	{
		$res .= xml(
			$tag, [{
				'type' => $type,
				'name' => "do-$cmdbutton\_$cmdnum",
				(($tag eq 'input' && length($param->{'text'})) ? ('value' => $param->{'text'}) : ()),
				%$opts,
			}, 
				(($tag eq 'button' && length($param->{'text'})) ? (0, $param->{'text'}) : ()),
				@contents,
			],
		);
	}
	return $res;
}

sub hidden
{
	my ($obj, $param) = get_param(@_);
	my $res = '';
	foreach my $i (sort keys %$param)
	{
		$res .= xml(
			'input', [{
				'type' => 'hidden',
				'name' => $i,
				'value' => $param->{$i},
			}],
		);
	}
	return $res;
}

sub style
{
	my ($obj, $param) = get_param(@_);
	my $rv;
	my @ks = sort keys %$param;
	my $ct = $#ks;
	foreach my $i (0..$ct)
	{
		my $k = $ks[$i];
		my $v = $param->{$k};
		$rv .= "$k: $param->{$k};";
		unless ($i == $ct)
		{
			$rv .= ' ';
		}
	}
	return $rv;
}

# apply a template with page reference
sub apply
{
	my ($obj, $tmpl, $data) = @_;
	$data->{'page'} ||= $obj;
	return $obj->template()->apply($tmpl, $data);
}

1;

