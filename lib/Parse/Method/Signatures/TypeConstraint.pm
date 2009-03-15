package Parse::Method::Signatures::TypeConstraint;

use Moose;
use MooseX::Types::Util;
use MooseX::Types::Moose qw/Str HashRef CodeRef/;
use Parse::Method::Signatures::Types qw/TypeConstraint/;

use namespace::clean -except => 'meta';

has ppi => (
  is       => 'ro',
  isa      => 'PPI::Element',
  required => 1,
  handles => {
    'to_string' => 'content'
  }
);

has tc => (
    is => 'ro',
    isa => TypeConstraint,
    lazy => 1,
    builder => '_build_tc',
);

has search_in_package => (
    is => 'ro',
    isa => ClassName,
    predicate => 'has_search_package'
);

has tc_callback => (
    is       => 'ro',
    isa      => CodeRef,
    default  => sub { \&find_registered_constraint },
);

sub find_registered_constraint {
    my ($self, $name) = @_;

    my $type;
    if ($self->has_search_package)
      $type = has_available_type_export($self->search_in_package, $name);

    my $registry = Moose::Util::TypeConstraints->get_type_constraint_registry;
    return $type || $registry->find_type_constraint($name) || $name;
}


sub _build_tc {
    my ($self) = @_;
    return $self->_walk_data($self->ppi);
}

sub _walk_data {
    my ($self, $data) = @_;

    my $res = $self->_union_node($data)
           || $self->_params_node($data)
           || $self->_str_node($data)
           || $self->_leaf($data)
      or confess 'failed to visit tc';
    return $res->();
}

sub _leaf {
    my ($self, $data) = @_;
    #return if ref($data);

    sub { $self->_invoke_callback($data->content) };
}

sub _union_node {
    my ($self, $data) = @_;
    return unless $data->isa('PPI::Statement::Expression::TCUnion');

    my @types = map { $self->_walk_data($_) } $data->children;
    sub {
      scalar @types == 1 ? @types
        : Moose::Meta::TypeConstraint::Union->new(type_constraints => \@types)
    };
}

sub _params_node {
    my ($self, $data) = @_;
    return unless $data->isa('PPI::Statement::Expression::TCParams');

    my @params = map { $self->_walk_data($_) } @{$data->params};
    my $type = $self->_invoke_callback($data->type);
    sub { $type->parameterize(@params) }
}


sub _str_node {
    my ($self, $data) = @_;
    return unless $data->isa('PPI::Token::StringifiedWord')
               || $data->isa('PPI::Token::Number')
               || $data->isa('PPI::Token::Quote');

    sub {
      $data->isa('PPI::Token::Number')
          ? $data->content
          : $data->string
    };
}

sub _invoke_callback {
    my $self = shift;
    $self->tc_callback->($self, @_);
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

Parse::Method::Signatures::TypeConstraint - turn parsed TC data into Moose TC object

=head1 DESCRIPTION

Class used to turn PPI elements into L<Moose::Meta::TypeConstraint> objects.

=head1 ATTRIBUTES

=head2 tc

=over

B<Lazy Build.>

=back

The L<Moose::Meta::TypeConstraint> object for this type constraint, built when
requested. L</tc_callback> will be called for each individual component type in
turn.

=head2 tc_callback

=over

B<Type:> CodeRef

B<Default:> L</find_registered_constraint>

=back

Callback used to turn type names into type objects. See
L<Parse::Method::Signatures/type_constraint_callback> for more details and an
example.

=head2 search_in_package

=over

B<Type:> ClassName

=back

If provided, then the default C<tc_callback> will search for L<MooseX::Types>
in this package.

=head1 METHODS

=head2 find_registered_constraint

Will search for an imported L<MooseX::Types> in L</search_in_package> (if
provided). Failing that it will ask the L<Moose::Meta::TypeConstraint::Registry>
for a type with the given name.

If all else fails, it will simple return the type as a string, so that Moose's
auto-vivification of classnames to type will work.

=head2 to_string

String representation of the type constraint, approximately as parsed.

=head1 SEE ALSO

L<Parse::Method::Signatures>, L<MooseX::Types>, L<MooseX::Types::Util>.

=head1 AUTHORS

Florian Ragwitz <rafl@debian.org>.

Ash Berlin <ash@cpan.org>.

=head1 LICENSE

Licensed under the same terms as Perl itself.

