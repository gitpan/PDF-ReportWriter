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

use constant bsize_x	=> 11 * in;		# x points in a B size page
use constant bsize_y	=> 17 * in;		# y points in a B size page

use constant legal_x	=> 11 * in;		# x points in a legal page
use constant legal_y	=> 14 * in;		# y points in a legal page

use constant TRUE	=> 1;
use constant FALSE	=> 0;

BEGIN {
	$PDF::ReportWriter::VERSION = '0.81';
}

sub new {
		
	my ( $class, $self ) = @_;
	
	bless $self, $class;
	
	if ( $self->{paper} eq "A4" ) {
		if ( $self->{orientation} eq "portrait" ) {
			$self->{page_width} = A4_x;
			$self->{page_height} = A4_y;
		} elsif ( $self->{orientation} eq "landscape" ) {
			$self->{page_width} = A4_y;
			$self->{page_height} = A4_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} elsif ( $self->{paper} eq "Letter" || $self->{paper} eq "letter" ) {
		if ( $self->{orientation} eq "portrait" ) {
			$self->{page_width} = letter_x;
			$self->{page_height} = letter_y;
		} elsif ( $self->{orientation} eq "landscape" ) {
			$self->{page_width} = letter_y;
			$self->{page_height} = letter_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} elsif ( $self->{paper} eq "bsize" || $self->{paper} eq "Bsize" ) {
		if ( $self->{orientation} eq "portrait" ) {
			$self->{page_width} = bsize_x;
			$self->{page_height} = bsize_y;
		} elsif ( $self->{orientation} eq "landscape" ) {
			$self->{page_width} = bsize_y;
			$self->{page_height} = bsize_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} elsif ( $self->{paper} eq "Legal" || $self->{paper} eq "legal" ) {
		if ( $self->{orientation} eq "portrait" ) {
			$self->{page_width} = legal_x;
			$self->{page_height} = legal_y;
		} elsif ( $self->{orientation} eq "landscape" ) {
			$self->{page_width} = legal_y;
			$self->{page_width} = legal_x;
		} else {
			die "Unsupported orientation: " . $self->{orientation} . "\n";
		}
	} else {
		die "Unsupported paper format: " . $self->{paper} . "\n";
	}
	
	# Create a new PDF document
	$self->{pdf} = PDF::API2->new;
	
	# Set some info stuff
	my $localtime = localtime time;
	
	$self->{pdf}->info(
				Author		=> $self->{info}->{Author},
				CreationDate	=> $localtime,
				Creator		=> "PDF::ReportWriter $PDF::ReportWriter::VERSION",
				Keywords	=> $self->{info}->{Keywords},
				ModDate		=> $localtime,
				Subject		=> $self->{info}->{Subject},
				Title		=> $self->{info}->{Title}
			  );
					
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
	
	return $self;
	
}

sub render_data {
	
	my ( $self, $data ) = @_;
	
	$self->{data} = $data;
		
	$self->{data}->{max_font_size} = 0; # We calculate this one now
	
	# Complete field definitions ...
	# ... calculate the position of each cell's borders and text positioning
	
	# Create a default background object if $self->{cell_borders} is set ( ie legacy support )
	if ( $self->{data}->{cell_borders} ) {
		$self->{data}->{background} = {
							border	=> "grey"
					      };
	}
	
	# Normal cells
	$self->setup_cell_definitions( $self->{data}->{fields}, "data" );
	
	# Page headers
	if ( $self->{data}->{page}->{header} ) {
		$self->setup_cell_definitions( $self->{data}->{page}->{header}, "page_header" );
	}
	
	# Page footers
	if ( $self->{data}->{page}->{footer} ) {
		$self->setup_cell_definitions( $self->{data}->{page}->{footer}, "page_footer" );
	} elsif ( ! $self->{data}->{page}->{footer} && ! $self->{data}->{page}->{footerless} ) {
		# Set a default page footer if we haven't been explicitely told not to
		$self->{data}->{page_footer_max_font_size} = 8;
		$self->{data}->{page}->{footer} = [
							{
								percent		=> 50,
								font_size	=> 8,
								text		=> "Rendered on %TIME%",
								align		=> "left"
							},
							{
								percent		=> 50,
								font_size	=> 8,
								text		=> "Page %PAGE% of %PAGES%",
								align		=> "right"
							}
						  ];
		$self->setup_cell_definitions( $self->{data}->{page}->{footer}, "page_footer" );
	}
	
	# Calculate the y space needed for page footers
	my $size_calculation = $self->calculate_y_needed(
								{
									fields		=> $self->{data}->{page}->{footer},
									max_font_size	=> $self->{data}->{page_footer_max_font_size}
								}
							);
	
	$self->{page_footer_and_margin} = $size_calculation->{current_height} + $self->{y_margin};
	
	# Same process for the group header / footer definitions, but there is some group-specific
	# stuff, so we process them separately to the above
	for my $group ( @{$self->{data}->{groups}} ) {
		
		for my $group_type ( qw / header footer / ) {
			
			my $x = $self->{x_margin};
			
			# Reset group's max_font_size setting
			$group->{$group_type . "_max_font_size"} = 0;
			
			for my $field ( @{$group->{$group_type}} ) {
				
				# The cell's left-hand border position
				$field->{x_border} = $x;
				
				# The cell's font size - user defined by cell, or from the report default
				if ( ! $field->{font_size} ) {
					$field->{font_size} = $self->{default_font_size};
				}
				
				# We also need to set the max_font_size
				if ( $field->{font_size} > $group->{$group_type . "_max_font_size"} ) {
					$group->{$group_type . "_max_font_size"} = $field->{font_size};
				}
				
				# The cell's text whitespace ( the minimum distance between the x_border and cell text )
				# Default to half the font size if not given
				if ( ! $field->{text_whitespace} ) {
					$field->{text_whitespace} = $field->{font_size} * 0.5;
				}
				
				# The cell's left-hand text position
				$field->{x_text} = $x + $field->{text_whitespace};
				
				# The cell's full width ( border to border )
				$field->{border_width} = ( $self->{page_width} - ( $self->{x_margin} * 2 ) ) * $field->{percent} / 100;
				
				# The cell's maximum width of text
				$field->{text_width} = $field->{border_width} - $field->{font_size};
				
				# Move along to the next position
				$x += $field->{border_width};
				
				# For aggregate functions, we need the name of the group, which is used later
				# to retrieve the aggregate values ( which are stored against the group,
				# hence the need for the group name ). However when rendering a row,
				# we don't have access to the group *name*, so storing it in the 'text'
				# key is a nice way around this
				
				if ( $field->{aggregate_source} ) {
					$field->{text} = $group->{name};
				}
				
				# Initialise group aggregate results
				$field->{group_results}->{$group->{name}} = 0;
				$field->{grand_aggregate_result}->{$group->{name}} = 0;
				
			}
			
		}
		
		# Set all group values to a special character so we recognise that we are entering
		# a new value for each of them ... particularly the GrandTotal group
		$group->{value} = "!";
		
	}
	
	# Create a new page if we have none ( ie at the start of the report )
	if ( ! $self->{page} ) {
		$self->new_page;
	}
	
	$self->{txt}->fillcolor("black");
	
	my $no_group_footer = TRUE; # We don't want a group footer on the first run
	
	# Main loop
	for my $row ( @{$self->{data}->{data_array}} ) {
		
		# Check if we're entering a new group
		$self->{need_data_header} = FALSE;
		
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
					push
						@{$self->{group_header_queue}},
						{
							group => $group,
							value => $$row[$group->{data_column}]
						};
				}
				$self->{need_data_header} = TRUE; # Remember that we need to render a data header afterwoods
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
	$self->{y} -= $self->{data}->{max_font_size} * 1.5;
	
}

sub setup_cell_definitions {
	
	my ( $self, $field_array, $type ) = @_;
	
	my $x = $self->{x_margin};
	
	for my $field ( @{$field_array} ) {
		
		# The cell's left-hand border position
		$field->{x_border} = $x;
		
		# The cell's font size - user defined by cell, or from the report default
		if ( ! $field->{font_size} ) {
			$field->{font_size} = $self->{default_font_size};
		}
		
		# The cell's text whitespace ( the minimum distance between the x_border and cell text )
		# Default to half the font size if not given
		if ( ! $field->{text_whitespace} ) {
			$field->{text_whitespace} = $field->{font_size} * 0.5;
		}
		
		# The cell's left-hand text position
		$field->{x_text} = $x + $field->{text_whitespace};
		
		# The cell's full width ( border to border )
		$field->{border_width} = ( $self->{page_width} - ( $self->{x_margin} * 2 ) ) * $field->{percent} / 100;
		
		# The cell's maximum width of text
		$field->{text_width} = $field->{border_width} - $field->{font_size};
		
		# We also need to set the max_font_size, but make sure we put it in the right place
		if ( $type eq "data" ) {
			if ( $field->{font_size} > $self->{data}->{max_font_size} ) {
				$self->{data}->{max_font_size} = $field->{font_size};
			}
			# Default to the data-level background if there is none defined for this cell
			# We don't do this for page headers / footers, because I don't think this
			# is appropriate default behaviour for these ( ie usually doesn't look good )
			if ( ! $field->{background} ) {
				$field->{background} = $self->{data}->{background};
			}
		} elsif ( $type eq "page_header" ) {
			if ( $field->{font_size} > $self->{data}->{page_header_max_font_size} ) {
				$self->{data}->{page_header_max_font_size} = $field->{font_size};
			}
		} elsif ( $type eq "page_footer" ) {
			if ( $field->{font_size} > $self->{data}->{page_footer_max_font_size} ) {
				$self->{data}->{page_footer_max_font_size} = $field->{font_size};
			}
		}
		
		# Move along to the next position
		$x += $field->{border_width};
		
	}
	
}

sub new_page {
	
	my $self = shift;
	
	# Create a new page	
	my $page = $self->{pdf}->page;
	
	# Set page dimensions
	$page->mediabox( $self->{page_width}, $self->{page_height} );
	
	# Create a new txt object for the page
	$self->{txt} = $page->text;
	
	# Set y to the top of the page
	$self->{y} = $self->{page_height} - $self->{y_margin};
	
	# Remember that we need to print a data header
	$self->{need_data_header} = TRUE;
	
	# Create a new gfx object for our lines
	$self->{line} = $page->gfx;
	
	# And a shape object for cell backgrounds and stuff
	# We *need* to call ->gfx with a *positive* value to make it render first ...
	#  ... otherwise it won't be the background - it will be the foreground!
	$self->{shape} = $page->gfx(1);
	
	# Append out page footer definition to an array - we store one per page, and render
	# them immediately prior to saving the PDF, so we can say "Page n of m" etc
	push @{$self->{page_footers}}, $self->{data}->{page}->{footer};
	
	# Push new page onto array of pages
	push @{$self->{pages}}, $page;
	       
	# Render page header if defined
	if ( $self->{data}->{page}->{header} ) {
		$self->render_row( $self->{data}->{page}->{header}, undef, "page_header", $self->{data}->{page_header_max_font_size} );
	}
	
}

sub group_header {
	
	# Renders a new group header
	
	my ( $self, $group, $value ) = @_;
	
	if ( $group->{name} ne "GrandTotals" ) {
		$self->{y} -= $group->{header_max_font_size};
	}
	
	$self->render_row( $group->{header}, $group->{value}, "group_header", $group->{header_max_font_size} );
	
}

sub group_footer {
	
	# Renders a new group footer
	
	my ( $self, $group ) = @_;
	
	my $y_needed = $self->{page_footer_and_margin} + $group->{footer_max_font_size};
	
	if ($self->{y} - $y_needed < 0) {
		$self->new_page;
	}
	
	$self->render_row( $group->{footer}, $group->{value}, "group_footer", $group->{footer_max_font_size} );
	
	# Reset group totals
	for my $field ( @{ $self->{data}->{fields} } ) {
		$field->{group_results}->{$group->{name}} = 0;
	}
	
}

sub calculate_y_needed {
	
	my ( $self, $options ) = @_;
	
	# Unpack options hash
	my $fields		= $options->{fields};
	my $max_font_size	= $options->{max_font_size};
	
	# For text, we allocate 1.5 times the font size,
	# so start with this value as the minimum $current_height
	my $current_height	= $max_font_size * 1.5;
	
	my ( $img_x, $img_y, $img_type );
	my $scale_ratio = 1; # Default is no scaling
	
	# Search for an image in the current row
	# If one is encountered, adjust our $y_needed according to scaling definition
	# Images can take up the full cell
	
	# *** TODO *** implement something similar ( or identical )
	# to $field->{textwhitespace} so images can have a whitespace border
	
	for my $field ( @{$options->{fields}} ) {
		
		if ( $field->{image} ) {
			
			my $y_scale_ratio;
			
			# *** TODO *** support use of images in memory instead of from files?
			( $img_x, $img_y, $img_type ) = imgsize( $field->{image}->{path} );
			
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
	
	# If we have queued group headers, calculate how much Y space they need
	
	# Note that at this point, $current_height is the height of the current row
	# We now introduce $y_needed, which is $current_height, PLUS the height of headers etc
	
	my $y_needed = $current_height;
	
	# *** TODO *** this will not work if there are *unscaled* images in the headers
	# Is it worth supporting this as well? Maybe.
	# Maybe later ...
	
	if ( $self->{group_header_queue} ) {
		for my $header ( @{$self->{group_header_queue}} ) {
			# We multiply by 1.5 for the standard text size
			# Then add another 1 for the gap between the previous data and the header ...
			#  ... see group_header() for details
			$y_needed += $header->{group}->{header_max_font_size} * 2.5;
		}
		# And also the data header if it's turned on
		if ( ! $self->{data}->{no_field_headers} ) {
			$y_needed += $max_font_size * 1.5;
		}
	}
	
	return {
			current_height	=> $current_height,
			y_needed	=> $y_needed,
			img_type	=> $img_type,
			img_x		=> $img_x,
			img_y		=> $img_y,
			scale_ratio	=> $scale_ratio
			
	       };
	
}

sub render_row {
	
	my ( $self, $fields, $row, $type, $max_font_size ) = @_;
	
	# $fields	- a hash of field definitions
	# $row		- the current row to render
	# $type		- possible values are:
	#			- header		- prints a row of field names
	#			- data			- prints a row of data
	#			- group_header		- prints a row of group header
	#			- group_footer		- prints a row of group footer
	#			- page_header		- prints a page header
	#			- page_footer		- prints a page footer
	
	# In the case of page footers, $row will be a hash with useful stuff like
	# page number, total pages, time, etc
	
	# Calculate the y space required, including queued group footers
	my $size_calculation = $self->calculate_y_needed(
								{
									fields		=> $fields,
									max_font_size	=> $max_font_size
								}
							);
	
	# Unpack size_calculation results ( easier to read like this )
	my $current_height	= $size_calculation->{current_height};
	my $y_needed		= $size_calculation->{y_needed};
	my $img_type		= $size_calculation->{img_type};
	my $img_x		= $size_calculation->{img_x};
	my $img_y		= $size_calculation->{img_y};
	my $scale_ratio		= $size_calculation->{scale_ratio};
	
	# Page Footer / New Page / Page Header if necessary, otherwise move down by $current_height
	# ( But don't force a new page if we're rendering a page footer )
	if ( $type ne "page_footer" && $self->{y} - ( $y_needed + $self->{page_footer_and_margin} ) < 0 ) {
		$self->new_page;
	}
	
	# Trigger any group headers that we have queued, but ONLY if we're in a data cycle
	if ( $type eq "data" ) {
		while ( my $queued_headers = pop @{$self->{group_header_queue}} ) {
			$self->group_header( $queued_headers->{group}, $queued_headers->{value} );
		}
	}
	
	if ( $type eq "data" && $self->{need_data_header} && !$self->{data}->{no_field_headers} ) {
		$self->render_row( $fields, 0, "header", $self->{data}->{max_font_size} );
	}
	
	$self->{y} -= $current_height;
	
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
				
				$self->{shape}->fillcolor( $colour );
				
				$self->{shape}->ellipse(
						$field->{x_border} + ( $field->{border_width} / 2 ),	# x centre
						$self->{y} + ( $current_height / 2 ),			# y centre
						$field->{border_width} / 2,				# length ( / 2 ... for some reason )
						$current_height / 2					# height ( / 2 ... for some reason )
					       );
				
				$self->{shape}->fill;
				
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
				
				$self->{shape}->fillcolor( $colour );
				
				$self->{shape}->rect(
						$field->{x_border},					# left border
						$self->{y},						# bottom border
						$field->{border_width},					# length
						$current_height						# height
					    );
				
				$self->{shape}->fill;
		
			}
					
		}
		
		if ( $field->{background}->{border} ) {
			
			# Cell Borders
			$self->{line}->strokecolor( $field->{background}->{border} );
			$self->{line}->move( $field->{x_border}, $self->{y} );
			$self->{line}->line( $field->{x_border} + $field->{border_width}, $self->{y} );
			$self->{line}->line( $field->{x_border} + $field->{border_width}, $self->{y} + $current_height );
			$self->{line}->line( $field->{x_border}, $self->{y} + $current_height );
			$self->{line}->line( $field->{x_border}, $self->{y} );
			$self->{line}->stroke;
				
		}
		
		# That's cell borders / backgrounds done
		
		# Now for the actual contents of the cell ...
		
		if ( $field->{image} ) {
			
			# *** TODO *** support use of images in memory instead of from files?
			my $gfx = $self->{pages}[ scalar@{$self->{pages}} - 1 ]->gfx;
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
				$img_y_pos = $self->{y} - ( ( $current_height - $img_y ) / 2 );
			} elsif ( $field->{align} && $field->{align} eq "right") {
				$img_x_pos = $field->{x_border} + ( $field->{border_width} - $img_x );
				$img_y_pos = $self->{y} - ( ( $current_height - $img_y ) / 2 );
			} else {
				$img_x_pos = $field->{x_border};
				$img_y_pos = $self->{y} - ( ( $current_height - $img_y ) / 2 );
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
				$self->{txt}->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Bold}, $field->{font_size} );
			} else {
				$self->{txt}->font( $self->{fonts}->{ ( $field->{font} || $self->{default_font} ) }->{Roman}, $field->{font_size} );
			}
			
			if ($type eq "header") {
				$string = $field->{name};
			} elsif ( $type eq "data" ) {
				$string = $$row[$field_counter];
			} elsif ( $type eq "group_header" ) {
				$string = $field->{text};
				$string =~ s/\?/$row/g;	# In the case of a group header, the $row variable is the group value
			} elsif ( $type eq "group_footer" ) {
				if ( exists($field->{aggregate_source}) ) {
					if ($field->{text} eq "GrandTotals") {
						$string = $self->{data}->{fields}[$field->{aggregate_source}]->{grand_aggregate_result};
					} else {
						$string = $self->{data}->{fields}[$field->{aggregate_source}]->{group_results}->{$field->{text}};
					}
				} else {
					$string =$field->{text};
				}
				$string =~ s/\?/$row/g; # In the case of a group footer, the $row variable is the group value
			} elsif ( $type =~ m/^page/ ) {
				# page_header or page_footer
				$string = $field->{text};
				$string =~ s/\%PAGE\%/$row->{current_page}/;
				$string =~ s/\%PAGES\%/$row->{total_pages}/;
				$string =~ s/\%TIME\%/$row->{current_time}/;
			}
			
			# Set colour or default to black
			if ($type eq "header") {
				$self->{txt}->fillcolor( $field->{header_colour} || "black" );
			} else {
				if ($field->{colour_func}) {
					if ($self->{debug}) {
						print "\nRunning colour_func() on data: " . $string . "\n";
					}
					$self->{txt}->fillcolor( $field->{colour_func}($string) || "black" );
				} else {
					$self->{txt}->fillcolor( $field->{colour} || "black" );
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
			while ($self->{txt}->advancewidth($string) > $field->{text_width}) {
				chop($string);
			}
			
			# Alignment
			if ( ( $field->{align} && ( $field->{align} eq "centre" || $field->{align} eq "center" ) ) || $type eq "header") {
				# Calculate the width of the string, and move to the right so there's an
				# even gap at both sides, and render left-aligned from there
				my $string_width = $self->{txt}->advancewidth($string);
				my $x_offset = ( $field->{text_width} - $string_width ) / 2;
				my $x_anchor = $field->{x_text} + $x_offset;
				$self->{txt}->translate( $x_anchor, $self->{y} + $field->{text_whitespace} );
				$self->{txt}->text($string);
			} elsif ( $field->{align} && $field->{align} eq "right") {
				$self->{txt}->translate ( $field->{x_text} + $field->{text_width}, $self->{y} + $field->{text_whitespace} );
				$self->{txt}->text_right($string);
			} else {
				# Default alignment if left-aligned
				$self->{txt}->translate( $field->{x_text}, $self->{y} + $field->{text_whitespace} );
				$self->{txt}->text($string);
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
	
}

sub save {
	
	my $self = shift;
	
	my $total_pages = scalar@{$self->{pages}};
	
	# We first loop through all the pages and add footers to them
	for my $this_page_no ( 0 .. $total_pages - 1 ) {
		
		$self->{txt} = $self->{pages}[$this_page_no]->text;
		my $localtime = localtime time;
		
		# Get the current_height of the footer - we have to move this much *above* the y_margin,
		# as our render_row() will move this much down before rendering
		my $size_calculation = $self->calculate_y_needed(
									{
										fields		=> $self->{page_footers}[$this_page_no],
										max_font_size	=> $self->{page_footer_max_font_size}
									}
								);
		
		$self->{y} = $self->{y_margin} + $size_calculation->{current_height};
		
		$self->render_row(
					$self->{page_footers}[$this_page_no],
					{
						current_page	=> $this_page_no + 1,
						total_pages	=> $total_pages,
						current_time	=> $localtime
					},
					"page_footer",
					$self->{page_footer_max_font_size}
				 );
		
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

The example below is purely as a reference inside this documentation to give you an idea of what goes
where. It is not intended as a working example - for a working example, see the demo application package,
distributed separately at http://entropy.homelinux.org/axis_not_evil

First we set up the top-level report definition and create a new PDF::ReportWriter object ...

$report = {

  destination        => "/home/dan/my_fantastic_report.pdf",
  paper              => "A4",
  orientation        => "portrait",
  font_list          => [ "Times" ],
  default_font       => "Times",
  default_font_size  => "10",
  x_margin           => 10 * mm,
  y_margin           => 10 * mm,
  info               => {
                            Author      => "Daniel Kasak",
                            Keywords    => "Fantastic, Amazing, Superb",
                            Subject     => "Stuff",
                            Title       => "My Fantastic Report"
                        }

};

my $pdf = PDF::ReportWriter->new( $report );

Next we define our page setup, with a page header ( we can also put a 'footer' object in here as well )

my $page = {

  header             => [
                                {
                                        percent        => 60,
                                        font_size      => 15,
                                        align          => "left",
                                        text           => "My Fantastic Report"
                                },
                                {
                                        percent        => 40,
                                        align          => "right",
                                        image          => {
                                                                  path          => "/home/dan/fantastic_stuff.png",
                                                                  scale_to_fit  => TRUE
                                                          }
                                }
                         ]

};

Define our fields - which will make up most of the report

my $fields = [

  {
     name               => "Date",                               # 'Date' will appear in field headers
     percent            => 35,                                   # The percentage of X-space the cell will occupy
     align              => "centre",                             # Content will be centred
     colour             => "blue",                               # Text will be blue
     font_size          => 12,                                   # Override the default_font_size with '12' for this cell
     header_colour      => "white"                               # Field headers will be rendered in white
  },
  {
     name               => "Item",
     percent            => 35,
     align              => "centre",
     header_colour      => "white",
  },
  {
     name               => "Appraisal",
     percent            => 30,
     align              => "centre",
     colour_func        => sub { red_if_fantastic(@_); },        # red_if_fantastic() will be called to calculate colour for this cell
     aggregate_function => "count"                               # Items will be counted, and the results stored against this cell
   }
   
];

I've defined a custom colour_func for the 'Appraisal' field, so here's the sub:

sub red_if_fantastic {

     my $data = shift;
     if ( $data eq "Fantastic" ) {
          return "red";
     } else {
          return "black";
     }

}

Define some groups ( or in this case, a single group )

my $groups = [
   
   {
      name           => "DateGroup",                             # Not particularly important - apart from the special group "GrandTotals"
      data_column    => 0,                                       # Which column to group on ( 'Date' in this case )
      header => [
      {
         percent           => 100,
         align             => "right",
         colour            => "white",
         background        => {                                  # Draw a background for this cell ...
                                   {
                                         shape     => "ellipse", # ... a filled ellipse ...
                                         colour    => "blue"     # ... and make it blue
                                   }
                              }
         text              => "Entries for ?"                    # ? will be replaced by the current group value ( ie the date )
      }
      footer => [
      {
         percent           => 70,
         align             => "right",
         text              => "Total entries for ?"
      },
      {
         percent           => 30,
         align             => "centre",
         aggregate_source  => 2                                  # Take figure from field 2 ( which has the aggregate_function on it )
      }
   }
   
];

We need a data array ...

my $data_array = $dbh->selectall_arrayref(
 "select Date, Item, Appraisal from Entries order by Date"
);

Note that you MUST order the data array, as above, if you want to use grouping.
PDF::ReportWriter doesn't do any ordering of data for you.

Now we put everything together ...

my $data = {
   
   background              => {                                  # Set up a default background for all cells ...
                                  border      => "grey"          # ... a grey border
                              },
   fields                  => $fields,
   groups                  => $groups,
   page                    => $page,
   data_array              => $data_array,
   headings                => {                                  # This is where we set up field header properties ( not a perfect idea, I know )
                                  background  => {
                                                     shape     => "box",
                                                     colour    => "darkgrey"
                                                 }
                              }
   
};

... and finally pass this into PDF::ReportWriter

$pdf->render_data( $data );

At this point, we can do something like assemble a *completely* new $data object,
and then run $pdf->render_data( $data ) again, or else we can just finish things off here:

$pdf->save;


=head1 CELL DEFINITIONS

PDF::ReportWriter renders all content the same way - in cells. Each cell is defined by a hash.
A report definition is basically a collection of cells, arranged at various levels in the report.

Each 'level' to be rendered is defined by an array of cells.
ie an array of cells for the data, an array of cells for the group header, and an array of cells for page footers.

Cell spacing is relative. You define a percentage for each cell, and the actual length of the cell is
calculated based on the page dimensions ( in the top-level report definition ).

A cell can have the following attributes

=head2 name

=over 4

The 'name' is used when rendering data headers, which happens whenever a new group or page is started.
It's not used for anything else - data must be arranged in the same order as the cells to 'line up' in
the right place.

You can disable rendering of field headers by setting no_field_headers in your data definition ( ie the
hash that you pass to the render() method ).

=back

=head2 percent

=over 4

The width of the cell, as a percentage of the total available width.
The actual width will depend on the paper definition ( size and orientation )
and the x_margin in your report_definition.

=back

=head2 font

=over 4

The font to use. In most cases, you would set up a report-wide default_font.
Only use this setting to override the default.

=back

=head2 font_size

=over 4

The font size. Nothing special here...

=back

=head2 colour

=over 4

The colour to use for rendering data ( and also group headers / footers ).

=back

=head2 header_colour

=over 4

The colour to use for rendering data headers ( ie field names ).

=back

=head2 text

=over 4

The text to display in the cell.

=back

=head2 image

=over 4

A hash with details of the image to render. See below for details.

=back

=head2 colour_func

=over 4

A user-defined sub that returns a colour based on the current data ( ie receives 1 argument: the current value )

=back

=head2 align

=over 4

Possible values are "left", "right" and "centre" ( or now "center", also ).

=back

=head2 aggregate_function

=over 4

Possible values are "sum" and "count". Setting this attribute will make PDF::ReportWriter carry out the selected function
and store the results ( attached to the cell ) for later use in group footers.

=back

=head2 type

=over 4

This key turns on formatting of data.
The only possible values currrently are 'currency' and 'currency:no_fill', which
are achived via Number::Format ( which spews warnings everywhere - they're harmless )

=back

=head2 background

=over 4

A hash containing details on how to render the background of the cell. See below.

=back

=head1 IMAGES

You can define images in any cell ( data, or group header / footer ).
The default behaviour is to render the image at its original size.
If the image won't fit horizontally, it is scaled down until it will.
Images can be aligned in the same way as other fields, with the 'align' key.

The images hash has the following keys:

=head2 path

=over 4

The full path to the image to render ( currently only supports png and jpg )
This key is the only required one

=back

=head2 scale_to_fit

=over 4

A boolean value, indicating whether the image should be scaled to fit the current cell or not.
Whether this is set or not, scaling will still occur if the image is too wide for the cell.

=back

=head2 height

=over 4

You can hard-code a height value if you like. The image will be scaled to the given height value,
to the extent that it still fits length-wise in the cell.

=back

=head1 BACKGROUNDS

You can define a background for any cell, including normal fields, group header & footers, etc.
For data headers ONLY, you must ( currently ) set them up per data set, instead of per field. In this case,
you add the background key to the 'headings' hash in the main data hash.

The background hash has the following keys:

=head2 shape

=over 4

Current options are 'box' or 'ellipse'. 'ellipse' is good for group headers.
'box' is good for data headers or 'normal' cell backgrounds. If you use an 'ellipse',
it tends to look better if the text is centred. More shapes are needed.
A 'round_box', with nice rounded edges, would be great. Send patches. 

=back

=head2 colour

=over 4

The colour to use to fill the background's shape. Keep in mind with data headers ( the automatic
headers that appear at the top of each data set ), that you set the *foreground* colour via the
field's 'header_colour' key, as there are ( currently ) no explicit definitions for data headers.

=back

=head2 border

=over 4

The colour ( if any ) to use to render the cell's border. If this is set, the border will be a rectangle,
around the very outside of the cell. You can have a shaped background and a border rendererd in the
same cell.

=back

=head1 GROUP DEFINITIONS

Groups have the following attributes:

=head2 name

=over 4

The name is used to identify which value to use in rendering aggregate functions ( see aggregate_source, below ).
Also, a special name, "GrandTotals" will cause PDF::ReportWriter to fetch *Grand* totals instead of group totals.
This negates the need to have an extra column of data in your data_array with all the same value ... which
is the only other way I can see of 'cleanly' getting GrandTotal functionality.

=back

=head2 data_column

=over 4

The data_column refers to the column ( starting at 0 ) of the data_array that you want to group on.

=back

=head2 header / footer

=over 4

Group headers and footers are defined in a similar way to field definitions ( and rendered by the same code ).
The difference is that the cell definition is contained in the 'header' and 'footer' hashes, ie the header and
footer hashes resemble a field hash. Consequently, most attributes that work for field cells also work for
group cells. Additional attributes in the header and footer hashes are:

=back

=head2 aggregate_source

=over 4

This is used to retrieve the results of an aggregate_function ( see above ).

=back

=head1 REPORT DEFINITION

Possible attributes for the report defintion are:

=head2 destination

=over 4

The path to the destination ( the pdf that you want to create ).

=back

=head2 paper

=over 4

Supported types are:

=over 4

A4

Letter

bsize

legal

=back

=back

=head2 orientation

=over 4

portrait or landscape

=back

=head2 font_list

=over 4

An array of font names ( from the corefonts supported by PDF::API2 ) to set up.
When you include a font 'family', a range of fonts ( roman, italic, bold, etc ) are created.

=back

=head2 default_font

=over 4

The name of the font type ( from the above list ) to use as a default ( ie if one isn't set up for a cell ).

=back

=head2 default_font_size

=over 4

The default font size to use if one isn't set up for a cell.
This is no longer required and defaults to 12 if one is not given.

=back

=head2 x_margin

=over 4

The amount of space ( left and right ) to leave as a margin for the report.

=back

=head2 y_margin

=over 4

The amount of space ( top and bottom ) to leave as a margin for the report.

=back

=head1 DATA DEFINITION

The data definition wraps up most of the previous definitions, apart from the report definition.
My goal ( with a future release ) is to support unlimited 'sections', which you'll be able to achieve
by passing new data definitions and calling the 'render' method. Currently this does not work, but
should not take too much to get it going.

Attributes for the data definition:

=head2 cell_borders

=over 4

Whether to render cell borders or not. This is a legacy option - not that there's any
pressing need to remove it - but this is a precursor to background->{border} support,
which can be defined per-cell.

Setting cell_borders in the data definition will cause all data cells to be filled out
with: background->{border} = "grey"

=back

=head2 no_field_headers

=over 4

Set to disable rendering field headers when beginning a new page or group.

=back

=head2 fields

=over 4

This is your field definition hash, from above.

=back

=head2 groups

=over 4

This is your group definition hash, from above.

=back

=head2 data_array

=over 4

This is the data to render.
You *MUST* sort the data yourself. If you are grouping by A, then B and you want all data
sorted by C, then make sure you sort by A, B, C. We currently don't do *any* sorting of data,
as I only intended this module to be used in conjunction with a database server, and database
servers are perfect for sorting data :)

=back

=head2 page

=over 4

This is a hash describing page headers and footers - see below.

=back

=head1 PAGE DEFINITION

=over 4

The page definition is a hash describing page headers and footers. Possible keys are:

=over 4

header

footer

=back

Each of these keys is an array of cell definitions. Unique to the page *footer* is the ability
to define the following special tags:

=over 4

%TIME%

%PAGE%

%PAGES%

=back

These will be replaced with the relevant data when rendered.

If you don't specify a page footer, one will be supplied for you. This is to provide maximum
compatibility with previous versions, which had page footers hard-coded. If you want to supress
this behaviour, then set a value for $self->{data}->{page}->{footerless}

=back

=head1 METHODS

=head2 new ( report_definition )

=over 4

Object constructor. Pass the report definition in.

=back

=head2 render_data ( data_definition )

=over 4

Renders the data passed in
You can call 'render_data' as many times as you want,
with different data and definitions.

=back

=head2 save

=over 4

Saves the pdf file ( in the location specified in the report definition ).

=back

=head1 AUTHORS

=over 4

Dan <dan@entropy.homelinux.org>

=back

=head1 BUGS

=over 4

I think you must be mistaken.

=back

=head1 Other cool things you should know about:

=over 4

This module is part of an umbrella project, 'Axis Not Evil', which aims to make
Rapid Application Development of database apps using open-source tools a reality.
The project includes:

Gtk2::Ex::DBI                 - forms

Gtk2::Ex::Datasheet::DBI      - datasheets

PDF::ReportWriter             - reports

All the above modules are available via cpan, or for more information, screenshots, etc, see:
http://entropy.homelinux.org/axis_not_evil

=back

=head1 Crank ON!

=cut
