#!/usr/bin/perl

# (C) Daniel Kasak: dan@entropy.homelinux.org
# See COPYRIGHT file for full license

# See 'man PDF::ReportWriter' for full documentation ... or of course continue reading

use strict;

no warnings;

package PDF::ReportWriter;

use PDF::API2;
use Number::Format;
use Image::Size;

use constant mm		=> 72/25.4;		# 25.4 mm in an inch, 72 points in an inch
use constant in		=> 72;			# 72 points in an inch
use constant A4_x	=> 210 * mm;		# x points in an A4 page ( 595.2755 )
use constant A4_y	=> 297 * mm;		# y points in an A4 page ( 841.8897 )
use constant letter_x	=> 8.5 * in;		# x points in a letter page
use constant letter_y	=> 11 * in;		# y points in a letter page

use constant TRUE	=> 1;
use constant FALSE	=> 0;

BEGIN {
	$PDF::ReportWriter::VERSION = '0.6';
}

# Globals
my ( $page, $txt, $x, $y, $fields_def, $page_width, $page_height, $line, $shape,
    $need_data_header, $page_footer_and_margin, @group_header_queue );

sub new {
		
	my ( $class, $self ) = @_;
	
	bless $self, $class;
	
	if ($self->{paper} eq "A4") {
		if ($self->{orientation} eq "portrait") {
			$page_width = A4_x;
			$page_height = A4_y;
		} elsif ($self->{orientation} eq "landscape") {
			$page_width = A4_y;
			$page_height = A4_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} elsif ($self->{paper} eq "letter") {
		if ($self->{orientation} eq "portait") {
			$page_width = letter_x;
			$page_height = letter_y;
		} elsif ($self->{orientation} eq "landscape") {
			$page_width = letter_y;
			$page_height = letter_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} else {
		die "Unsupported paper format: " . $self->{paper} . "\n";
	}
	
	# Create a new PDF document
	$self->{pdf} = PDF::API2->new;
	
	# Add requested fonts
	for my $font ( @{$self->{font_list}} ) {
		# Roman fonts are easy
		$self->{fonts}->{$font}->{Roman} = $self->{pdf}->corefont(			$font,			-encoding => 'latin1');
		# The rest are f'n ridiculous. Adobe either didn't think about this, or are just stoopid
		if ($font eq "Courier") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Courier-Bold",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Courier-Oblique",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Courier-BoldOblique",	-encoding => 'latin1');
		}
		if ($font eq "Helvetica") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Helvetica-Bold",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Helvetica-Oblique",	-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Helvetica-BoldOblique",-encoding => 'latin1');
		}
		if ($font eq "Times") {
			$self->{fonts}->{$font}->{Bold} = $self->{pdf}->corefont(		"Times-Bold",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{Italic} = $self->{pdf}->corefont(		"Times-Italic",		-encoding => 'latin1');
			$self->{fonts}->{$font}->{BoldItalic} = $self->{pdf}->corefont(		"Times-BoldItalic",	-encoding => 'latin1');
		}
	}
	
	# Default report font size to 12 in case a default hasn't been supplied
	if ( !$self->{default_font_size} ) {
		$self->{default_font_size} = 12;
	}
	
	$self->{page_count} = -1; # new_page adds one to the count ... this allows us to start at zero
	$self->new_page;
	
	return $self;
	
}

sub render_data {
	
	my ( $self, $data ) = @_;
	
	$self->{data} = $data;
	
	$txt->fillcolor("black");
	
	# Complete field definitions ...
	# ... calculate the position of each cell's borders and text positioning
	
	# This is now calculated, but *used* to be user-defined.
	# We therefore reset this value, in case the user has defined one
	$self->{data}->{max_font_size} = 0;
		
	$page_footer_and_margin = ( 8 * 1.5 ) + $self->{y_margin}; # usually we multiply the font-size by 1.5 ( for cell borders ) but this gives too much y-space in this case
	
	$x = $self->{x_margin};
	
	for my $field ( @{$self->{data}->{fields}} ) {
		
		# The cell's left-hand border position
		$field->{x_border} = $x;
		
		# The cell's font size - user defined by cell, or from the report default
		if ( !$field->{font_size} ) {
			$field->{font_size} = $self->{default_font_size};
		}
		
		# We also need to set the max_font_size
		if ( $field->{font_size} > $self->{data}->{max_font_size} ) {
			$self->{data}->{max_font_size} = $field->{font_size};
		}
		
		# The cell's text whitespace ( the minimum distance between the x_border and cell text )
		# Default to half the font size if not given
		if ( !$field->{text_whitespace} ) {
			$field->{text_whitespace} = $field->{font_size} * 0.5;
		}
		
		# The cell's left-hand text position
		$field->{x_text} = $x + $field->{text_whitespace};
		
		# The cell's full width ( border to border )
		$field->{border_width} = ( $page_width - ( $self->{x_margin} * 2 ) ) * $field->{percent} / 100;
		
		# The cell's maximum width of text
		$field->{text_width} = $field->{border_width} - $field->{font_size};
		
		# Move along to the next position
		$x += $field->{border_width};
		
	}
	
	# Same process for the group header / footer definitions
	for my $group ( @{$self->{data}->{groups}} ) {
		
		for my $group_type ( qw / header footer / ) {
			
			$x = $self->{x_margin};
			
			# Reset group's max_font_size setting
			$group->{$group_type . "_max_font_size"} = 0;
			
			for my $field ( @{$group->{$group_type}} ) {
				
				# The cell's left-hand border position
				$field->{x_border} = $x;
				
				# The cell's font size - user defined by cell, or from the report default
				if ( !$field->{font_size} ) {
					$field->{font_size} = $self->{default_font_size};
				}
				
				# We also need to set the max_font_size
				if ( $field->{font_size} > $group->{$group_type . "_max_font_size"} ) {
					$group->{$group_type . "_max_font_size"} = $field->{font_size};
				}
				
				# The cell's text whitespace ( the minimum distance between the x_border and cell text )
				# Default to half the font size if not given
				if ( !$field->{text_whitespace} ) {
					$field->{text_whitespace} = $field->{font_size} * 0.5;
				}
				
				# The cell's left-hand text position
				$field->{x_text} = $x + $field->{text_whitespace};
				
				# The cell's full width ( border to border )
				$field->{border_width} = ( $page_width - ( $self->{x_margin} * 2 ) ) * $field->{percent} / 100;
				
				# The cell's maximum width of text
				$field->{text_width} = $field->{border_width} - $field->{font_size};
				
				# Move along to the next position
				$x += $field->{border_width};
				
				# For aggregate functions, we need the name of the group, which is used later
				# to retrieve the aggregate values ( which are stored against the group,
				# hence the need for the group name ). However when rendering a row,
				# we don't have access to the group *name*, so storing it in the 'text'
				# key is a nice way around this
				
				if ($field->{aggregate_source}) {
					$field->{text} = $group->{name};
				}
				
				# Initialise group aggregate results
				$field->{group_results}->{$group->{name}} = 0;
				$field->{grand_aggregate_result}->{$group->{name}} = 0;
				
			}
			
		}
		
		# Set all group values to a special character so we recognise that we are entering a new value for each of them ...
		#  ... particularly the GrandTotal group
		$group->{value} = "!";
		
	}
	
	my $no_group_footer = TRUE; # We don't want a group footer on the first run
	
	# Main loop
	for my $row ( @{$self->{data}->{data_array}} ) {
		
		# Check if we're entering a new group
		$need_data_header = FALSE;
		
		foreach my $group ( reverse @{$self->{data}->{groups}} ) {
			if ( $group->{value} ne $$row[$group->{data_column}] ) {
				if ( ! $no_group_footer && scalar(@{$group->{footer}}) ) {
					$self->group_footer($group);
				}
				# Store new group value
				$group->{value} = $$row[$group->{data_column}];
				# Queue headers for rendering in the data cycle
				# ... prevents rendering a header before the last group footer is done
				if (scalar(@{$group->{header}})) {
					push @group_header_queue, {
									group => $group,
									value => $$row[$group->{data_column}]
								  };
				}
				$need_data_header = 1; # Remember that we need to render a data header afterwoods
			}
		}
		
		$self->render_row( $self->{data}->{fields}, $row, "data", $self->{data}->{max_font_size} );
		
		$no_group_footer = FALSE; # Turn group footers on
		
	}
	
	# The final group footers will not have been triggered ( only happens when we get a *new* group ), so we do them now
	foreach my $group ( reverse @{$self->{data}->{groups}} ) {
		if (scalar(@{$group->{footer}})) {
			$self->group_footer($group);
		}
	}
	
	# Move down some more at the end of this pass
	$y -= $self->{data}->{max_font_size} * 1.5;
	
}

sub new_page {
	
	my $self = shift;
	
	$self->{page_count} ++;
	$self->{pages}[$self->{page_count}] = $self->{pdf}->page;
	
	# Create a reference to the above page ( ease strain on eyes )
	$page = $self->{pages}[$self->{page_count}];
	
	# Set page dimensions
	$page->mediabox($page_width, $page_height);
	
	# Create a new txt object for the page
	$txt = $page->text;
	
	# Set y to the top of the page
	$y = $page_height - $self->{y_margin};
	
	# Remember that we need to print a data header
	$need_data_header = TRUE;
	
	# Create a new gfx object for our lines
	$line = $page->gfx;
	$line->strokecolor("grey");
	
	# And a shape object for cell backgrounds and stuff
	# We *need* to call ->gfx with a positive value to make it render first ...
	#  ... otherwise is won't be the background - it will be the foreground
	$shape = $page->gfx(1);
	
}

sub group_header {
	
	# Renders a new group header
	
	my ( $self, $group, $value ) = @_;
	
	$self->render_row( $group->{header}, $group->{value}, "group_header", $group->{header_max_font_size} );
	
	# Move down again for to separate the header from the data ( or data header )
	$y -= $group->{header_max_font_size};
	
}

sub group_footer {
	
	# Renders a new group footer
	
	my ( $self, $group ) = @_;
	
	my $y_needed = $page_footer_and_margin + $group->{footer_max_font_size};
	
	if ($y - $y_needed < 0) {
		$self->new_page;
	}
	
	$self->render_row( $group->{footer}, $group->{value}, "group_footer", $group->{footer_max_font_size} );
	
	# Reset group totals
	for my $field ( @{ $self->{data}->{fields} } ) {
		$field->{group_results}->{$group->{name}} = 0;
	}
	
}

sub render_row {
	
	my ( $self, $fields, $row, $type, $max_font_size, $no_cell_border ) = @_;
	
	# $fields	- a hash of field definitions
	# $row		- the current row to render
	# $type		- possible values are:
	#			- header		- prints a row of field names
	#			- data			- prints a row of data
	#			- group_header		- prints a row of group header
	#			- group_footer		- prints a row of group footer
	
	# First, calculate the height of the current row
	
	# For text, we allocate 1.5 times the font size,
	# so start with this value as the minimum $current_height
	my $current_height = $max_font_size * 1.5;
	
	
	# Search for an image in the current row
	# If one is encountered, adjust our $y_needed according to scaling definition
	# Images can take up the full cell
	# *** TODO *** implement something similar ( or identical ) to $field->{textwhitespace}
	
	my ( $img_x, $img_y, $img_type );
	my $scale_ratio = 1; # Default is no scaling
	
	for my $field ( @{$fields} ) {
		
		if ( $field->{image} ) {
			
			my $y_scale_ratio;
			
			# *** TODO *** support use of images in memory instead of from files?
			( $img_x, $img_y, $img_type ) = imgsize($field->{image}->{path});
			
			if ( $field->{image}->{height} ) {
				# The user has defined an image height
				$y_scale_ratio = $field->{image}->{height} / $img_y;
			} elsif ( $field->{image}->{scale_to_fit} ) {
				# We're scaling to fit the current cell
				$y_scale_ratio = $current_height / $img_y;
			} else {
				# no scaling or hard-coded height defined
				$y_scale_ratio = 1;
			};
			
			# A this point, no matter what scaling, fixed size, or lack of
			# other instructions, we still have to test whether the image will fit
			# length-wise in the cell
			my $x_scale_ratio = $field->{border_width} / $img_x;
			
			# Choose the smallest of x & y scale ratios to ensure we'll fit both ways
			if ( $y_scale_ratio < $x_scale_ratio ) {
				$scale_ratio = $y_scale_ratio;
			} else {
				$scale_ratio = $x_scale_ratio;
			}
			
			# Set our new image dimensions based on this scale_ratio
			$img_x *= $scale_ratio;
			$img_y *= $scale_ratio;
			$current_height = $img_y;
			
		}
		
	}
	
	my $y_needed = $current_height;
	
	# If we have queued group headers, calculate how much Y space they need
	
	# *** TODO *** this will not work if there are *unscaled* images in the headers
	# Is it worth supporting this as well? Maybe. Maybe later ...
	
	if ( scalar(@group_header_queue) ) {
		for my $header ( @group_header_queue ) {
			$y_needed += $header->{group}->{header_max_font_size} * 1.5;
		}
		# And also the data header if it's turned on
		if ( ! $self->{data}->{no_field_headers} ) {
			$y_needed += $max_font_size * 1.5;
		}
	}
	
	# Page Footer / New Page / Page Header if necessary, otherwise move down by $current_height
	if ( $y - ( $y_needed + $page_footer_and_margin ) < 0 ) {
		$self->new_page;
	}
	
	# Trigger any group headers that we have queued, but ONLY if we're in a data cycle
	if ($type eq "data") {
		while ( my $queued_headers = pop @group_header_queue ) {
			$self->group_header( $queued_headers->{group}, $queued_headers->{value} );
		}
	}
	
	if ($type eq "data" && $need_data_header && !$self->{data}->{no_field_headers}) {
		$self->render_row( $fields, 0, "header", $self->{data}->{max_font_size}, TRUE );
	}
	
	$y -= $current_height;
	
	# Render row
	my $field_counter = 0;
	
	for my $field ( @{$fields} ) {
		
		# Render an ellipse, box, or cell borders
		if ( $field->{background}->{shape} || ( $type eq "header" && $self->{data}->{headings}->{background} ) ) {
			
			if ( $field->{background}->{shape} eq "ellipse"
			    || ( $type eq "header"
					&& $self->{data}->{headings}->{background}
					&& $self->{data}->{headings}->{background}->{shape} eq "ellipse" )) {
				
				# Ellipse
				my $colour;
				
				if ( $type eq "header" ) {
					$colour = $self->{data}->{headings}->{background}->{colour};
				} else {
					$colour = $field->{background}->{colour};
				}
				
				$shape->fillcolor( $colour );
				
				$shape->ellipse(
						$field->{x_border} + ( $field->{border_width} / 2 ),	# x centre
						$y + ( $current_height / 2 ),				# y centre
						$field->{border_width} / 2,				# length ( / 2 ... for some reason )
						$current_height / 2					# height ( / 2 ... for some reason )
					       );
				
				$shape->fill;
				
			} elsif ( $field->{background}->{shape} eq "box" || ( $type eq "header"
					&& $self->{data}->{headings}->{background}
					&& $self->{data}->{headings}->{background}->{shape} eq "box" )) {
				
				# Box
				my $colour;
				
				if ( $type eq "header" ) {
					$colour = $self->{data}->{headings}->{background}->{colour};
				} else {
					$colour = $field->{background}->{colour};
				}
				
				$shape->fillcolor( $colour );
				
				$shape->rect(
						$field->{x_border},					# left border
						$y,							# bottom border
						$field->{border_width},					# length
						$current_height						# height
					    );
				
				$shape->fill;
				
			}
		
		} elsif ( $self->{data}->{cell_borders}  && !$no_cell_border && ! ( $type eq "group_header" || $type eq "group_footer" ) ) {
			# Cell Borders
			$line->move( $field->{x_border}, $y );
			$line->line( $field->{x_border} + $field->{border_width}, $y );
			$line->line( $field->{x_border} + $field->{border_width}, $y + $current_height );
			$line->line( $field->{x_border}, $y + $current_height );
			$line->line( $field->{x_border}, $y );
			$line->stroke;
		}
		
		if ( $field->{image} ) {
			
			# *** TODO *** support use of images in memory instead of from files?
			my $gfx = $self->{pages}[$self->{page_count}]->gfx;
			my $image;
			
			# *** TODO *** Add support for more image types
			if ( $img_type eq "PNG" ) {
				$image = $self->{pdf}->image_png($field->{image}->{path});
			} elsif ( $img_type eq "JPG" ) {
				$image = $self->{pdf}->image_jpeg($field->{image}->{path});
			}
			
			my ( $img_x_pos, $img_y_pos );
			
			# Alignment
			if ( $field->{align} && ( $field->{align} eq "centre" || $field->{align} eq "center" ) ) {
				$img_x_pos = $field->{x_border} + ( ( $field->{border_width} - $img_x ) / 2 );
				$img_y_pos = $y - ( ( $current_height - $img_y ) / 2 );
			} elsif ( $field->{align} && $field->{align} eq "right") {
				$img_x_pos = $field->{x_border} + ( $field->{border_width} - $img_x );
				$img_y_pos = $y - ( ( $current_height - $img_y ) / 2 );
			} else {
				$img_x_pos = $field->{x_border};
				$img_y_pos = $y - ( ( $current_height - $img_y ) / 2 );
			};
			
			$gfx->image(
					$image,			# The image
					$img_x_pos,		# X
					$img_y_pos,		# Y
					$scale_ratio		# scale
				   );
			
		} else {
			
			# Figure out what we're putting into the current cell and set the font and size
			# We currently default to Bold if we're doing a header
			# We also check for an specific font for this field, or fall back on the report default
			my $string;
			
			if ($type =~ /header/ ) {
				$txt->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Bold}, $field->{font_size} );
			} else {
				$txt->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Roman}, $field->{font_size} );
			}
			
			if ($type eq "header") {
				$string = $field->{name};
			} elsif ($type eq "data") {
				$string = $$row[$field_counter];
			} elsif ($type eq "group_header") {
				$string = $field->{text};
				$string =~ s/\?/$row/g;	# In the case of a group header, the $row variable is the group value
			} elsif ($type eq "group_footer") {
				if (exists($field->{aggregate_source})) {
					if ($field->{text} eq "GrandTotals") {
						$string = $self->{data}->{fields}[$field->{aggregate_source}]->{grand_aggregate_result};
					} else {
						$string = $self->{data}->{fields}[$field->{aggregate_source}]->{group_results}->{$field->{text}};
					}
				} else {
					$string =$field->{text};
				}
				$string =~ s/\?/$row/g; # In the case of a group footer, the $row variable is the group value
			}
			
			# Set colour or default to black
			if ($type eq "header") {
				$txt->fillcolor( $field->{header_colour} || "black" );
			} else {
				if ($field->{colour_func}) {
					if ($self->{debug}) {
						print "\nRunning colour_func() on data: " . $string . "\n";
					}
					$txt->fillcolor( $field->{colour_func}($string) || "black" );
				} else {
					$txt->fillcolor( $field->{colour} || "black" );
				}
			}
			
			# Apply type formatting ( eg currency )
			if ( $field->{type} && $field->{type} =~ /currency/ && $type ne "header" ) {
				my $decimal_fill = 1;
				if ($field->{type} eq "currency:no_fill") {
					$decimal_fill = 0;
				}
				my $dollar_formatter = new Number::Format(
										thousands_sep	=> ',',
										decimal_point	=> '.',
										decimal_fill	=> $decimal_fill,
										int_curr_symbol	=> 'USD'
									 );
				$string = "\$" . $dollar_formatter->format_number($string);
			}
			
			# Make sure the current string fits inside the current cell
			while ($txt->advancewidth($string) > $field->{text_width}) {
				chop($string);
			}
			
			# Alignment
			if ( ( $field->{align} && ( $field->{align} eq "centre" || $field->{align} eq "center" ) ) || $type eq "header") {
				# Calculate the width of the string, and move to the right so there's an even gap at both sides, and render left-aligned from there
				my $string_width = $txt->advancewidth($string);
				my $x_offset = ( $field->{text_width} - $string_width ) / 2;
				my $x_anchor = $field->{x_text} + $x_offset;
				$txt->translate( $x_anchor, $y + $field->{text_whitespace} );
				$txt->text($string);
			} elsif ( $field->{align} && $field->{align} eq "right") {
				$txt->translate ( $field->{x_text} + $field->{text_width}, $y + $field->{text_whitespace} );
				$txt->text_right($string);
			} else {
				# Default alignment if left-aligned
				$txt->translate( $field->{x_text}, $y + $field->{text_whitespace} );
				$txt->text($string);
			}
			
			# Now perform aggregate functions if defined
			if ( $type eq "data" && $field->{aggregate_function} ) {
				if ($field->{aggregate_function} eq "sum") {
					
					for my $group ( @{$self->{data}->{groups}} ) {
						$field->{group_results}->{$group->{name}} += $$row[$field_counter] || 0;
					}
					
					$field->{grand_aggregate_result} += $$row[$field_counter] || 0;
					
				} elsif ($field->{aggregate_function} eq "count") {
					
					for my $group ( @{$self->{data}->{groups}} ) {
						$field->{group_results}->{$group->{name}} += 1;
					}
					
					$field->{grand_aggregate_result} += 1;
					
				}
			} 
			
		}
		
		$field_counter ++;
		
	}
	
	#$y -= $current_height;
	
}

sub save {
	
	my $self = shift;
	
	# TODO:
	# - Add $self->render_page_footers
	# - Integrate option for legacy behaviour ( ie `page n of m` and render date )
	
	# We first loop through all the pages and add footers to them
	for my $this_page_no (0 .. $self->{page_count}) {
		
		$txt = $self->{pages}[$this_page_no]->text;
		$txt->fillcolor("black");
		
		$txt->font( $self->{fonts}->{Times}->{Bold}, 8 );
		
		$txt->translate( $self->{x_margin} + 4, $self->{y_margin} );
		$txt->text("Rendered on " . localtime time);
		
		$txt->translate( $page_width - $self->{x_margin} - 4, $self->{y_margin} );
		$txt->text_right("Page " . ($this_page_no + 1) . " of " . ($self->{page_count} + 1) . " pages");
		
	}
	
	$self->{pdf}->saveas($self->{destination});
	$self->{pdf}->end();
}

1;

=head1 NAME

PDF::ReportWriter

=head1 DESCRIPTION

PDF::ReportWriter is designed to create high-quality business reports, for archiving or printing.

=head1 USAGE

For a full example of all the features of PDF::ReportWriter, please see the Axis Not Evil demo application package,
which is distributed separately, at http://entropy.homlinux.org/axis_not_evil
Formatting in man pages is difficult, as is maintaining large examples in multiple places. Appologies.

=head1 FIELD DEFINITIONS

A field definition can have the following attributes

=head2 name

The 'name' is used when rendering field headers, which happens whenever a new group or page is started.
You can disable rendering of field headers by setting no_field_headers in your data definition.

=head2 percent

The width of the field, as a percentage of the total available width.
The actual width will depend on the paper definition ( size and orientation )
and the x_margin in your report_definition.

=head2 font

The font to use. In most cases, you would set up a report-wide default_font.
Only use this setting to override the default.

=head2 font_size

The font size. Nothing special here...

=head2 colour

The colour to use for rendering data ( and also group headers / footers ).

=head2 header_colour

The colour to use for rendering data headers ( ie the field names ).

=head2 text

The text to display in the field.

=head2 image

A hash with details of the image to render. See below for details.

=head2 colour_func

A user-defined sub that returns a colour based on the current data ( ie receives 1 argument: the current value )

=head2 align

Possible values are "left", "right" and "centre" ( or now "center", also ).

=head2 aggregate_function

Possible values are "sum" and "count". Setting this attribute will make PDF::ReportWriter carry out the selected function
and store the results ( attached to the field ) for later use in group footers.

=head2 type

This key turns on formatting of data.
The only possible values currrently are 'currency' and 'currency:no_fill', which
are achived via Number::Format ( which spews warnings everywhere - they're harmless )

=head2 background

A hash containing details on how to render the background of the cell. See below.

=head1 IMAGES

You can define images in any cell ( data, or group header / footer ).
The default behaviour is to render the image at its original size.
If the image won't fit horizontally, it is scaled down until it will.
Images can be aligned in the same way as other fields, with the 'align' key.

The images hash has the following keys:

=head2 path

The full path to the image to render ( currently only supports png and jpg )
This key is the only required one

=head2 scale_to_fit

A boolean value, indicating whether the image should be scaled to fit the current cell or not.
Whether this is set or not, scaling will still occur if the image is too wide for the cell.

=head2 height

You can hard-code a height value if you like. The image will be scaled to the given height value,
to the extent that it still fits length-wise in the cell.

=head1 BACKGROUNDS

You can define a background for any cell, including normal fields, group header & footers, etc.
For data headers ONLY, you must ( currently ) set them up per data set, instead of per field. In this case,
you add the background key to the 'headings' hash in the main data hash.

The background hash has the following keys:

=head2 shape

Current options are 'box' or 'ellipse'. 'ellipse' is good for group headers.
'box' is good for data headers or 'normal' cell backgrounds. If you use an 'ellipse',
it tends to look better if the text is centred. More shapes are needed.
A 'round_box', with nice rounded edges, would be great. Send patches. 

=head2 colour

The colour to use to fill the background's shape. Keep in mind with data headers ( the automatic
headers that appear at the top of each data set ), that you set the *foreground* colour via the
field's 'header_colour' key, as there are ( currently ) no explicit definitions for data headers.

=head1 GROUP DEFINITIONS

Groups have the following attributes:

=head2 name

The name is used to identify which value to use in rendering aggregate functions ( see aggregate_source, below ).
Also, a special name, "GrandTotals" will cause PDF::ReportWriter to fetch *Grand* totals instead of group totals.
This negates the need to have an extra column of data in your data_array with all the same value ... which
is the only other way I can see of 'cleanly' getting GrandTotal functionality.

=head2 data_column

The data_column refers to the column ( starting at 0 ) of the data_array that you want to group on.

=head2 header / footer

Group headers and footers are defined in a similar way to field definitions ( and rendered by the same code ).
The difference is that the cell definition is contained in the 'header' and 'footer' hashes, ie the header and footer hashes resemble a field hash.
Consequently, most attributes that work for field cells also work for group cells. Additional attributes in the header and footer hashes are:

=head2 aggregate_source

This is used to retrieve the results of an aggregate_function ( see above ).

=head1 REPORT DEFINITION

Possible attributes for the report defintion are:

=head2 destination

The path to the destination ( the pdf that you want to create ).

=head2 paper

The only paper types currently supported are A4 and Letter. And I haven't tested Letter...

=head2 orientation

portrait or landscape

=head2 font_list

An array of font names ( from the corefonts supported by PDF::API2 ) to set up.
When you include a font 'family', a range of fonts ( roman, italic, bold, etc ) are created.

=head2 default_font

The name of the font type ( from the above list ) to use as a default ( ie if one isn't set up for a cell ).

=head2 default_font_size

The default font size to use if one isn't set up for a cell.
This is no longer required and defaults to 12 if one is not given.

=head2 x_margin

The amount of space ( left and right ) to leave as a margin for the report.

=head2 y_margin

The amount of space ( top and bottom ) to leave as a margin for the report.

=head1 DATA DEFINITION

The data definition wraps up most of the previous definitions, apart from the report definition.
My goal ( with a future release ) is to support unlimited 'sections', which you'll be able to achieve
by passing new data definitions and calling the 'render' method. Currently this does not work, but
should not take too much to get it going.

Attributes for the data definition:

=head2 cell_borders

Whether to render cell borders or not.

=head2 no_field_headers

Set to disable rendering field headers when beginning a new page or group.

=head2 fields

This is your field definition hash, from above.

=head2 groups

This is your group definition hash, from above.

=head2 data_array

This is the data to render.


=head1 METHODS

=head2 new ( report_definition )

Object constructor. Pass the report definition in.

=head2 render_data ( data_definition )

Renders the data passed in
You can call 'render_data' as many times as you want,
with different data and definitions

=head2 save

Saves the pdf file ( in the location specified in the report definition ).

=head1 AUTHORS

Dan <dan@entropy.homelinux.org>

=head1 BUGS

I think you must be mistaken.

=head1 Other cool things you should know about:

This module is part of an umbrella project, 'Axis Not Evil', which aims to make
Rapid Application Development of database apps using open-source tools a reality.
The project includes:

Gtk2::Ex::DBI                 - forms

Gtk2::Ex::Datasheet::DBI      - datasheets

PDF::ReportWriter             - reports

All the above modules are available via cpan, or for more information, screenshots, etc, see:
http://entropy.homelinux.org/axis_not_evil

=head1 Crank ON!

=cut