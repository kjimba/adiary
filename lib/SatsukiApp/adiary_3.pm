use strict;
#-------------------------------------------------------------------------------
# adiary_3.pm (C)nabe@abk
#-------------------------------------------------------------------------------
# ・画像管理
# ・ブログの設定
# ・記事、コメントなどの削除関連
#-------------------------------------------------------------------------------
use SatsukiApp::adiary ();
use SatsukiApp::adiary_2 ();
package SatsukiApp::adiary;
################################################################################
# ■画像管理
################################################################################
#-------------------------------------------------------------------------------
# ●画像dir関連の初期化
#-------------------------------------------------------------------------------
sub init_image_dir {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir = $self->blogimg_dir();
	$ROBJ->mkdir($dir);
	$ROBJ->mkdir($dir . '.trashbox/');	# ごみ箱フォルダ

	# ブォルダリストの生成
	$self->genarete_imgae_dirtree();
}

#-------------------------------------------------------------------------------
# ●画像ディレクトリツリーの生成
#-------------------------------------------------------------------------------
sub genarete_imgae_dirtree {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	if ($self->{blogid} eq '') { return -1; }

	my $dir   = $self->blogimg_dir();
	my $tree  = $self->get_dir_tree($dir);
	my $trash = $self->get_dir_tree($dir . '.trashbox/', '.trashbox/');	# ゴミ箱

	$tree->{name} = '/';
	$tree->{key}  = '/';
	$trash->{name} = '.trashbox/';
	$trash->{key}  = '.trashbox/';
	my $json = $self->generate_json([$tree, $trash], ['name', 'key', 'date', 'count', 'children']);
	$ROBJ->fwrite_lines( $self->{blogpub_dir} . 'images.json', $json);

	return $tree->{count};
}

#-------------------------------------------------------------------------------
# ●ディレクトリ階層の全データ取得
#-------------------------------------------------------------------------------
sub get_dir_tree {
	my $self = shift;
	my $dir  = shift;
	my $path = shift;
	my $ROBJ = $self->{ROBJ};

	my $list = $ROBJ->search_files($dir, {dir=>1});
	@$list = sort {		# '@'(0x40)を最後に表示する仕組み
		my $x = (ord($a)==0x40) cmp (ord($b)==0x40);
		$x ? $x : $a cmp $b;
	} @$list;

	my @dirs;
	my $files=0;
	my $cnt  =0;	# ファイル数カウント
	foreach(@$list) {
		if (substr($_,-1) ne '/') {
			# ただのファイル
			$files++;
			next;
		}
		# ディレクトリ
		my $d    = $ROBJ->fs_decode($_);
		my $tree = $self->get_dir_tree("$dir$_", "$path$d");
		$tree->{name} = $d;
		push(@dirs, $tree);
		$cnt += $tree->{count};
	}

	my $h = { key => $path, date => (stat($dir))[9], count => ($cnt + $files) };
	if (@dirs) {
		$h->{children} = \@dirs;
	}
	return $h;
}

#-------------------------------------------------------------------------------
# ●ディレクトリ内のファイル一覧取得
#-------------------------------------------------------------------------------
sub load_image_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};

	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	my @ary;
	foreach(@$files) {
		my @st = stat("$dir$_");
		$ROBJ->fs_decode(\$_);
		push(@ary,{
			name => $_,
			size => $st[7],
			date => $st[9],
			isImg=> $self->is_image($_)
		});
	}
	# サムネイル生成
	if (@ary) {
		$self->make_thumbnail($dir, $files);
	}

	my $json = $self->generate_json(\@ary, ['name', 'size', 'date', 'isImg', 'children']);
	return (0, $json);
}

#-------------------------------------------------------------------------------
# ●ディレクトリ内のEXIFあり画像一覧
#-------------------------------------------------------------------------------
sub load_exif_files {
	my $self = shift;
	my $dir  = $self->image_folder_to_dir( shift );	# 値check付
	my $ROBJ = $self->{ROBJ};
	if (!-r $dir) {
		return(-1,'["msg":"Folder not found"]');
	}

	my $files = $ROBJ->search_files( $dir );
	my $jpeg = $ROBJ->loadpm('Jpeg');
	my @ary;
	foreach(@$files) {
		if ($_ !~ /\.jpe?g$/i) { next; }
		if (! $jpeg->check_exif("$dir$_")) { next; }
		push(@ary, $_);
	}

	my $json = $self->generate_json(\@ary);
	return (0, $json);
}

#-------------------------------------------------------------------------------
# ●サムネイル生成
#-------------------------------------------------------------------------------
sub make_thumbnail {
	my $self = shift;
	my $dir  = shift;
	my $files= shift || [];
	my $opt  = shift || {};
	my $ROBJ = $self->{ROBJ};

	$ROBJ->mkdir("${dir}.thumbnail/");
	foreach(@$files) {
		$ROBJ->fs_encode(\$_);
		my $thumb = "${dir}.thumbnail/$_.jpg";
		# すでに存在したら生成しない
		if (!$opt->{force} && -r $thumb) { next; }

		my $isImage = $self->is_image($_);
		if ($isImage) {
			if ($opt->{del_exif} && $_ =~ /\.jpe?g$/i) {
				my $jpeg = $ROBJ->loadpm('Jpeg');
				$jpeg->strip("$dir$_");
			}
			my $r = $self->make_thumbnail_for_image($dir, $_, $opt->{size});
			if (!$r) { next; }
		}
		my $r = $self->make_thumbnail_for_notimage($dir, $_);
		if (!$r) { next; }

		# サムネイル生成に失敗したとき
		my $icon = $self->{album_icons} . $self->{album_allow_ext}->{'..'};
		if ($_ =~ m/\.(\w+)$/) {
			my $ext = $1;
			$ext =~ tr/A-Z/a-z/;
			my $exts = $self->load_album_allow_ext();
			my $file = $self->{album_allow_ext}->{$ext};
			if ($file) {
				$icon = $self->{album_icons} . $file;
			}
		}
		$ROBJ->file_copy($icon, $thumb);	# アイコンをコピー
	}
}

#-------------------------------------------------
# ○サムネイルパスを取得（for import_img() ）
#-------------------------------------------------
sub get_thumbnail_file {
	my $self = shift;
	my $dir  = shift;
	my $ROBJ = $self->{ROBJ};
	$ROBJ->mkdir("${dir}.thumbnail/");
	return "${dir}.thumbnail/" . (shift) . ".jpg";
}

#-------------------------------------------------
# ○画像ファイル
#-------------------------------------------------
sub make_thumbnail_for_image {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $size = int(shift) || 120;
	my $ROBJ = $self->{ROBJ};

	# リサイズ
	if ($size <  60) { $size= 60; }
	if (800 < $size) { $size=800; }

	# Windowsで日本語ファイル名がなぜか読み書きできない
	my $tmpfile;
	if ($^O eq 'MSWin32' && $ROBJ->{FsConvert}) {
		$tmpfile = $self->blogimg_dir() . '.imagetmp' . rand();
	}

	my $img = $self->load_image_magick( 'jpeg:size'=>"$size x $size" );
	if (!$img) { return -99; }
	my ($w, $h);
	eval {
		my $f = "$dir$file";
		if ($tmpfile &&  $f =~ /[^\x20-\x7e]/) {
			rename($f, $tmpfile);
			$img->Read( $tmpfile );
			rename($tmpfile, $f);
		} else {
			$img->Read( $f );
		}
		$img = $img->[0];
		$img->AutoOrient();
		($w, $h) = $img->Get('width', 'height');
	};
	if ($@) { return -1; }	# load 失敗

	if ($w<=$size && $h<=$size) {
		$size = 0;	# resize しない
	} elsif ($w>$h) {
		$h = int($h*($size/$w));
		$w = $size;
	} else {
		$w = int($w*($size/$h));
		$h = $size;
	}
	if ($size) {	# リサイズ
		eval { $img->Thumbnail(width => $w, height => $h); };
		if ($@) {
			# ImageMagick-5.x.x以前
			eval { $img->Resize(width => $w, height => $h, blur => 0.7); };
			if ($@) { return -2; }	# サムネイル作成失敗
			eval { $img->Strip(); }	# exif削除
 		}
	}
	# ファイルに書き出し
	$img->Set( quality => ($self->{album_jpeg_quality} || 80) );
	my $f = "${dir}.thumbnail/$file.jpg";
	if ($tmpfile && $f =~ /[^\x20-\x7e]/) {
		$tmpfile .= '.jpg';
		$img->Write( $tmpfile );
		rename($tmpfile, $f);
	} else {
		$img->Write( $f );
	}
	return 0;
}

#-------------------------------------------------
# ○その他のファイル
#-------------------------------------------------
sub make_thumbnail_for_notimage {
	my $self = shift;
	my $dir  = shift;	# 実パス
	my $file = shift;
	my $ROBJ = $self->{ROBJ};

	# サイズ処理
	my $size  = 120;
	my $fsize = $self->{album_font_size};
	if($fsize < 6) { $fsize = 6; }
	my $fpixel = int($fsize*1.3333 + 0.999);
	my $f_height = $fpixel*3 +2;	# bottom padding = 2

	# キャンパス生成
	my $img = $self->load_image_magick();
	if (!$img) { return -99; }
	$img->Set(size => $size . 'x' . $size);
	$img->ReadImage('xc:white');

	# 拡張子アイコンの読み込み
	my $exts = $self->load_album_allow_ext();
	my $icon_dir  = $self->{album_icons};
	my $icon_file = $exts->{'.'};
	if ($self->is_image($file)) {
		$icon_file = $exts->{'.img'};	# 画像読み込みエラー時
	} elsif ($file =~ m/\.(\w+)$/) {
		my $ext = $1;
		$ext =~ tr/A-Z/a-z/;
		if ($exts->{$1}) {
			$icon_file = $exts->{$1};
		}
	}
	if (!-r "$icon_dir$icon_file") {	# 読み込めない時はdefaultアイコン
		$icon_file = $exts->{'.'};
	}
	my $icon = $self->load_image_magick();
	eval {
		$icon->Read( $icon_dir . $icon_file );

		my ($x, $y) = $icon->Get('width', 'height');
		$x = ($size - $x) / 2;
		$y =  $size - $f_height -$y -1;		# default 72 + 1 + 47 = 120
		$img->Composite(image=>$icon, compose=>'Over', x=>$x, y=>$y);
	};

	# 画像情報の書き込み
	my $album_file = $self->{album_font};
	if ($self->{album_font} && -r $album_file) {
		my @st = stat("$dir$file");
		my $tm = $ROBJ->print_tmf("%Y/%m/%d %H:%M", $st[9]);
		my $fs = $self->size_format($st[7]);
		my $name = $file;
		my $code = $ROBJ->{SystemCode};
		$ROBJ->fs_decode(\$name);
		if ($code ne 'UTF-8') {
			my $jcode = $ROBJ->load_codepm();
			$name = $jcode->from_to($name, $code, 'UTF-8');
		}
		if ($dir =~ m|/\.trashbox/|) {	# ゴミ箱内？
			$self->remove_trash_timestamp($name);
		}
		$self->image_magick_text_encode( $name );
		my $text = "$name\r\n$tm\r\n$fs";
		$img->Annotate(
			text => $text,
			font => $album_file,
			x => 3,
			y => ($size - $f_height + $fpixel),	# 最初の行の baseline 基準なので1行下げる
			pointsize => $fsize
		);
	}

	# ファイルに書き出し
	$img->Set( quality => 98 );

	# patch for windows
	my $f = "${dir}.thumbnail/$file.jpg";
	if ($^O eq 'MSWin32' && $ROBJ->{FsConvert} &&  $f =~ /[^\x20-\x7e]/) {
		my $tmpfile = $self->blogimg_dir() . '.imagetmp'  . rand() . '.jpg';
		$img->Write( $tmpfile );
		rename($tmpfile, $f);
	} else {
		$f =~ s/%/%%/g;
		$img->Write( $f );
	}
	return 0;
}

sub size_format() {
	my $self = shift;
	my $s = shift;
	if ($s > 104857600) {	# 100MB
		$s = int(($s+524288)/1048576);
		$s =~ s/(\d{1,3})(?=(?:\d\d\d)+(?!\d))/$1,/g;
		return $s . ' MB';
	}
	if ($s > 1023487) { return sprintf("%.3g", $s/1048576) . ' MB'; }
	if ($s >     999) { return sprintf("%.3g", $s/1024   ) . ' KB'; }
	return $s . ' Byte';
}

sub image_magick_text_encode {
	my $self = shift;
	foreach(@_) {		# See more https://imagemagick.org/api/annotate.php
		$_ =~ s/%%/%/g;
		$_ =~ s/&/&amp;/g;
		$_ =~ s/</&lt;/g;
		$_ =~ s/>/&gt;/g;
	}
	return @_;
}

#-------------------------------------------------------------------------------
# ●画像のアップロード
#-------------------------------------------------------------------------------
sub image_upload_form {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $size = $form->{size};	# サムネイルサイズ
	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付

	# アップロード
	my $count_s = 0;
	my $count_f = 0;
	my $ary = $form->{"file_ary"} || [];

	my @files;
	foreach(@$ary) {
		if (!ref($_)) { next; }

		my $fname = $_->{name};
		if ($fname eq '') { next; }

		if ($self->do_upload( $dir, $_ )){
			# $ROBJ->message('Upload fail: %s', $fname);
			$count_f++;
			next;
		}
		$count_s++;
		$ROBJ->message('Upload: %s', $fname);
		push(@files, $fname);
	}

	# ファイルが残ってたら削除
	foreach(@$ary) {
		if (!ref($_)) { next; }
		my $tmp = $_->{tmp};
		if ($tmp) { $ROBJ->file_delete($tmp); }
	}

	# サムネイル生成
	$self->make_thumbnail( $dir, \@files, {
		size     => $form->{size},
		del_exif => $form->{del_exif}
	});

	# フォルダリストの再生成
	$self->genarete_imgae_dirtree();

	# メッセージ
	return wantarray ? ($count_s, $count_f, \@files) : $count_f;
}

#-------------------------------------------------------------------------------
# ●ajax用の画像のアップロード
#-------------------------------------------------------------------------------
sub ajax_image_upload {
	my $self = shift;
	my $h = $self->do_ajax_image_upload( @_ );
	return $self->generate_json($h);
}
sub do_ajax_image_upload {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	# 画像フォルダ初期化
	$self->init_image_dir();

	# ディレクトリ作成
	my $dir = $self->image_folder_to_dir_and_create( $form->{folder} );

	my ($cs, $cf, $files) = $self->image_upload_form( $form );
	my %h;
	$h{ret}  = $cf ? 1 : 0;
	$h{fail} = $cf;
	$h{success} = $cs;
	$h{dir} = $dir;
	my @ary;
	foreach(@$files) {
		push(@ary,{
			name => $_,
			isImg=> $self->is_image($_)
		});
	}
	$h{files} = \@ary;
	return \%h;
}

#---------------------------------------------------------------------
# ●アップロードの実処理
#---------------------------------------------------------------------
sub do_upload {
	my $self = shift;
	my $dir  = shift;
	my $file_h = shift;
	my $ROBJ = $self->{ROBJ};

	# ハッシュデータ（フォームデータの確認）
	my $file_name = $file_h->{name};
	my $file_size = $file_h->{size};
	my $tmp_file  = $file_h->{tmp};		# 読み込んだファイルデータ(tmp file)
	if (!$self->check_file_name($file_name)) {
		$ROBJ->message("File name error : %s", $file_h->{name});
		return 2;
	}

	# 拡張子チェック
	if (! $self->album_check_ext($file_name)) { 
		$ROBJ->message("File extension error : %s", $file_name);
		return 3;
	}

	# ファイルの保存
	my $save_file = $dir . $ROBJ->fs_encode($file_name);
	if (-e $save_file && !$file_h->{overwrite}) {	# 同じファイルが存在する
		if ((-s $save_file) != $file_size) {	# ファイルサイズが同じならば、同一と見なす
			$ROBJ->message('Save failed ("%s" already exists)', $file_name);
			return 10;
		}
	} else {
		my $fail;
		if ($tmp_file) {
			if ($ROBJ->file_move($tmp_file, $save_file)) { $fail=21; }
		} else {
			if ($ROBJ->fwrite_lines($save_file, $file_h->{data})) { $fail=22; }
		}
		if ($fail) {	# 保存失敗
			$ROBJ->message("File can't write '%s'", $file_name);
			return $fail;
		}
	}
	# サムネイル削除
	$ROBJ->file_delete( "${dir}.thumbnail/$file_name.jpg" );
	return 0;	# 成功
}

#-------------------------------------------------------------------------------
# ●サムネイルの再生成
#-------------------------------------------------------------------------------
sub remake_thumbnail {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary};
	my $size  = $form->{size};

	# filesの値チェック
	foreach(@$files) {
		if (!$self->check_file_name($_)) { return -1; }
	}

	# サムネイル生成
	$self->make_thumbnail( $dir, $files, {
		size     => $form->{size},
		del_exif => $form->{del_exif},
		force    => 1
	});

	return 0;
}

#-------------------------------------------------------------------------------
# ●exifの除去
#-------------------------------------------------------------------------------
sub remove_exifjpeg {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir   = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary};

	# filesの値チェック
	foreach(@$files) {
		if (!$self->check_file_name($_)) { return -1; }
	}

	# Exif削除
	my $jpeg = $ROBJ->loadpm('Jpeg');
	my $fail = 0;
	foreach(@$files) {
		if (!$self->is_image($_) || $_ !~ /\.jpe?g$/i) { next; }
		$ROBJ->fs_encode(\$_);
		my $r = $jpeg->strip("$dir$_");
		$fail += $r ? 1 : 0;
	}
	return $fail;
}

#-------------------------------------------------------------------------------
# ●フォルダの作成
#-------------------------------------------------------------------------------
sub create_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $name = $self->chop_slash( $form->{name} );
	if ( !$self->check_file_name($name) ) { return -1; }

	$ROBJ->fs_encode(\$name);
	my $r = $ROBJ->mkdir("$dir$name") ? 0 : 1;
	$ROBJ->mkdir("$dir$name/.thumbnail");

	return $r;
}

#-------------------------------------------------------------------------------
# ●フォルダ名の変更
#-------------------------------------------------------------------------------
sub rename_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $self->chop_slash( $form->{old}  );
	my $name = $self->chop_slash( $form->{name} );
	$ROBJ->fs_encode(\$old );
	$ROBJ->fs_encode(\$name);
	if ( !$self->check_file_name($old ) ) { return -2; }
	if ( !$self->check_file_name($name) ) { return -1; }

	return rename("$dir$old", "$dir$name") ? 0 : 1;
}

#-------------------------------------------------------------------------------
# ●ファイルの移動
#-------------------------------------------------------------------------------
sub move_files {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $from = $self->image_folder_to_dir( $form->{from} ); # 値check付
	my $to   = $self->image_folder_to_dir( $form->{to}   ); # 値check付

	my $src_trash = ($form->{from} =~ m|^\.trashbox/|);	# 移動元がゴミ箱？
	my $des_trash = ($form->{to}   =~ m|^\.trashbox/|);	# 移動先がゴミ箱？
	if ($src_trash && $des_trash) {
		# ゴミ箱内移動ならファイル名に日付付加しない
		$src_trash = $des_trash = 0;
	}

	my $files = $form->{file_ary} || [];
	my @fail;
	my $tm = $ROBJ->print_tmf("%Y%m%d-%H%M%S");
	foreach(@$files) {
		if ( !$self->check_file_name($_) ) {
			push(@fail, $_);
			next;
		}
		$ROBJ->fs_encode(\$_);
		my $src = $_;
		my $des = $_;
		#---------------------------------
		# ゴミ箱にファイルを移動
		#---------------------------------
		if ($des_trash && !-d "$from$_") {
			my $x = rindex($des, '.');
			if ($x > 0) {
				$des = substr($des, 0, $x) . ".#$tm" . substr($des, $x);
			} else {
				$des .= ".#$tm";
			}
		}
		#---------------------------------
		# ゴミ箱からファイルを移動
		#---------------------------------
		if ($src_trash && !-d "$from$_") {
			$self->remove_trash_timestamp($des);
		}
		#---------------------------------
		# 同じファイル名が存在する
		#---------------------------------
		if (-e "$to$des") {
			push(@fail, $_);
			next;
		}
		#---------------------------------
		# リネーム（移動）
		#---------------------------------
		if (!rename("$from$src", "$to$des")) {
			push(@fail, $_);
			next;
		}

		# ファイルを移動した場合、サムネイルも移動
		if (-d "$to$des") { next; }
		# $ROBJ->mkdir("${to}.thumbnail/");
		if (!rename("${from}.thumbnail/$src.jpg", "${to}.thumbnail/$des.jpg")) {
			# 移動失敗時はサムネイル消去
			unlink("${from}.thumbnail/$src.jpg");
		}
	}
	my $f = $#fail+1;
	return wantarray ? ($f, \@fail) : $f;
}

sub remove_trash_timestamp {
	my $self = shift;
	foreach(@_) {
		$_ =~ s/(.*)\.#\d\d\d\d\d\d\d\d-\d\d\d\d\d\d/$1/;
	}
}

#-------------------------------------------------------------------------------
# ●ファイル名の変更
#-------------------------------------------------------------------------------
sub rename_file {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $old  = $form->{old};
	my $name = $form->{name};
	$ROBJ->fs_encode(\$old );
	$ROBJ->fs_encode(\$name);

	if ( !$self->check_file_name($old ) || !$self->album_check_ext($old ) ) { return -2; }
	if ( !$self->check_file_name($name) || !$self->album_check_ext($name) ) { return -1; }

	my $r  = rename("$dir$old", "$dir$name");
	my $r2;
	# 画像ファイルのみ移動を試みる
	if ($self->is_image($old) && $self->is_image($name)) {
		$r2 = rename("$dir.thumbnail/$old.jpg", "$dir.thumbnail/$name.jpg");
	}

	if ($r && !$r2) {
		# サムネイルだけ失敗時、古いサムネイルの削除
		$ROBJ->file_delete( "${dir}.thumbnail/$old.jpg" );
		# 新しいサムネイル生成
		$self->make_thumbnail( $dir, [$name], {
			size  => $form->{size},
			force => 1
		});
	}

	return ($r ? 0 : 1);
}

#-------------------------------------------------------------------------------
# ●ファイルを削除する
#-------------------------------------------------------------------------------
sub delete_files {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir  = $self->image_folder_to_dir( $form->{folder} ); # 値check付
	my $files = $form->{file_ary} || [];
	my @fail;
	foreach(@$files) {
		if ( !$self->check_file_name($_) ) {
			push(@fail, $_);
			next;
		}
		my $file = $_;
		$ROBJ->fs_encode(\$file);
		my $r = unlink("$dir$file");
		if (!$r) {
			push(@fail, $_);
			next;
		}
		unlink("${dir}.thumbnail/$file.jpg");
	}
	my $f = $#fail + 1;
	return wantarray ? ($f, \@fail) : $f;
}

#-------------------------------------------------------------------------------
# ●フォルダを削除する
#-------------------------------------------------------------------------------
sub delete_folder {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};

	my $folder = $form->{folder};
	if ($folder eq '' || $folder eq '/') {
		return -1;
	}

	my $dir = $self->image_folder_to_dir( $folder );
	my $ret = $ROBJ->dir_delete($dir) ? 0 : 1;

	$ROBJ->mkdir($self->blogimg_dir() . '.trashbox/');
	return $ret;
}

#-------------------------------------------------------------------------------
# ■アルバム関連サブルーチン
#-------------------------------------------------------------------------------
sub load_image_magick {
	eval { require Image::Magick; };
	if ($@) { return ; }
	return Image::Magick->new(@_);
}

#-------------------------------------------------------------------------------
# ○画像フォルダ→実ディレクトリ
#-------------------------------------------------------------------------------
sub image_folder_to_dir {
	my ($self, $folder) = @_;
	$folder =~ s!(^|/)\.+/!$1!g;
	$folder =~ s|/+|/|g;
	$folder =~ s|/*$|/|;
	$folder =~ s|^/||;
	$folder =~ s|[\x00-\x1f]| |g;
	$self->{ROBJ}->fs_encode(\$folder);
	return $self->blogimg_dir() . $folder;
}

sub image_folder_to_dir_and_create {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};

	my $dir = $self->image_folder_to_dir(@_);
	my @dirs;
	while ($dir && !-d $dir) {
		unshift(@dirs, $dir);
		$dir =~ s|[^/]*/?$||;
	}
	foreach(@dirs) {
		$ROBJ->mkdir($_);
	}
	return $dir;
}

#-------------------------------------------------------------------------------
# ○画像フォルダ名/ファイル名チェック
#-------------------------------------------------------------------------------
sub check_file_name {
	my ($self, $file) = @_;
	if ($file eq '' || $file =~ /^\./) { return 0; }	# ng
	# 制御コードや / 等の使用不可文字
	if ($file =~ m![\x00-\x1f/:\\\*\?\"<>|]!) { return 0; }	# Windows準拠
	return 1;	# ok
}
# 最後のスラッシュを取り除く
sub chop_slash {
	my ($self, $folder) = @_;
	if (substr($folder,-1) eq '/') { chop($folder); }
	return $folder;
}

#-------------------------------------------------------------------------------
# ○画像ファイルか拡張子判定
#-------------------------------------------------------------------------------
sub is_image {
	my ($self, $f) = @_;
	$f =~ tr/A-Z/a-z/;
	return ($f =~ m/\.(\w+)$/ && $self->{album_image_ext}->{$1});
}

#-------------------------------------------------------------------------------
# ○許可拡張子か判定
#-------------------------------------------------------------------------------
sub album_check_ext {
	my ($self, $f) = @_;
	# if ($self->{trust_mode}) { return 1; }	## 危険すぎるので無効に
	$self->load_album_allow_ext();

	while($f =~ /^(.*)\.([^\.]+)$/) {
		$f = $1;
		if (!$self->album_check_ext_one($2)) { return 0; }
	}
	return 1;
}

sub album_check_ext_one {
	my ($self, $ext) = @_;
	$ext =~ tr/A-Z/a-z/;
	if ($self->{album_image_ext}->{$ext} || $self->{album_allow_ext}->{$ext}) { return 1; }

	# 特殊な文字を含むか、数字で始まる
	return ($ext =~ /[^\w]/ || $ext =~ /^\d/);
}

#-------------------------------------------------------------------------------
# ○その他拡張子のロード
#-------------------------------------------------------------------------------
sub load_album_allow_ext {
	my $self = shift;
	if (!$self->{album_allow_ext}->{'.'}) {
		$self->{ROBJ}->call('album/_load_extensions');
	}
	return $self->{album_allow_ext};
}

################################################################################
# ■設定関連
################################################################################
#-------------------------------------------------------------------------------
# ●ブログの設定変更（保存）
#-------------------------------------------------------------------------------
sub save_blogset {
	my $self = shift;
	my $ROBJ = $self->{ROBJ};
	my $auth = $ROBJ->{Auth};
	my ($new_set, $blogid, $opt) = @_;

	# 権限確認
	my $blog;
	if ($blogid eq '') {
		if (! $self->{blog_admin}) { $ROBJ->message('Operation not permitted'); return 10; }
		$blogid = $self->{blogid};
		$blog   = $self->{blog};
	} else {
		# 他のブログ or デフォルト設定
		if (! $auth->{isadmin}) { $ROBJ->message('Operation not permitted'); return 11; }
		$blog = $self->load_blogset( $blogid );
		if (! $blog) { $ROBJ->message("Blog '%s' not found", $blogid); return 12; }
	}

	if ($blogid ne '*') {
		# 通常のブログ設定保存
		$self->update_blogset($blogid, $new_set);

		# プライベートモードチェック
		$self->save_private_mode( $blogid );

		# ブログ一覧情報に保存
		$self->update_bloginfo($blogid, {
			private   => $blog->{private},
			blog_name => $blog->{blog_name}
		});
	} else {
		# デフォルトのブログ設定値保存
		# 新規設定値をマージ
		$ROBJ->into($blog, $new_set);	# %$blog <- %$new_set

		# 固定値
		$blog->{arts} = 0;
		$blog->{coms} = 0;

		# ファイルに保存
		$ROBJ->fwrite_hash($self->{my_default_setting_file}, $blog);
	}

	return 0;
}

#-------------------------------------------------------------------------------
# ●プライベートモードの現在の状態保存
#-------------------------------------------------------------------------------
sub save_private_mode {
	my $self = shift;
	my $blogid = shift;
	my $ROBJ = $self->{ROBJ};
	my $blog = $self->load_blogset($blogid);

	my $postfix = $blog->{blogpub_dir_postfix};
	my $evt_name;
	if ($blog->{private} && $postfix eq '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid );
		$evt_name = "PRIVATE_MODE_ON";
	} elsif (!$blog->{private} && $postfix ne '') {
		$postfix = $self->change_blogpub_dir_postfix( $blogid, 0 );
		$evt_name = "PRIVATE_MODE_OFF";
	} else {
		return ;	# 特に変更がなければ何もしない
	}
	if (!defined $postfix) {
		$ROBJ->error('Rename failed blog public directory (%s)', $blogid);
		return 1;
	}
	my $old_dir = $self->blogpub_dir();
	$self->update_blogset($blog, 'blogpub_dir_postfix', $postfix);
	my $new_dir = $self->blogpub_dir();
	$self->{blogpub_dir} = $new_dir;

	# pub/<uid>/ 以下に保存してあるファイルのパス変更
	my $len = length($old_dir);
	foreach(keys(%$blog)) {
		if (substr($blog->{$_}, 0, $len) ne $old_dir) { next; }
		$blog->{$_} = $new_dir . substr($blog->{$_}, $len);
	}

	$self->call_event($evt_name);
	$self->rebuild_blog();
}

#-------------------------------------------------------------------------------
# ●ブログ公開ディレクトリ名の変更
#-------------------------------------------------------------------------------
sub change_blogpub_dir_postfix {
	my $self = shift;
	my $blogid = shift;
	my $len = (defined $_[0]) ? shift : ($self->{sys}->{dir_postfix_len} || $self->{dir_postfix_len});
	my $ROBJ = $self->{ROBJ};

	my $postfix = '';
	if ($len > 0) {
		if (32<$len) { $len=32; }
		$postfix = $ROBJ->generate_nonce($len);
		$postfix =~ s/\W/-/g;
		$postfix = '.' . $postfix;
	}

	# ディレクトリ名変更
	my $cur_dir = $self->blogpub_dir($blogid);
	chop($cur_dir);
	my $new_dir = $cur_dir;
	$new_dir =~ s|\.[^./]+$||;
	$new_dir .= $postfix;

	# リネーム
	my $r = rename( $cur_dir, $new_dir );
	if (!$r) { return undef; }

	return $postfix;
}

################################################################################
# ■記事やコメントの状態変更
################################################################################
#-------------------------------------------------------------------------------
# ●記事の表示状態変更、削除する
#-------------------------------------------------------------------------------
sub edit_articles {
	my ($self, $mode, $keylist, $opt) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $auth = $ROBJ->{Auth};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	if (ref($keylist) ne 'ARRAY' || !@$keylist) {
		return (0,0);
	}
	$keylist = [ map { int($_) } @$keylist ];

	# 初期状態設定
	my $blogid = $self->{blogid};
	if ($self->{blog}->{edit_by_author_only} && !$self->{blog_admin}) {
		# 他人の記事は編集できないので、IDが一致するかチェックする
		my $id = $auth->{id};
		my $ary = $DB->select_match("${blogid}_art", 'pkey', $keylist, '*cols', ['pkey','id']);
		my @pkeys;
		foreach(@$ary) {
			if ($_->{id} ne $id) { next; }
			push(@pkeys, $_->{pkey});
		}
		if (!@pkeys) {
			# 該当記事なし
			return wantarray ? (0,0) : 0;
		}
		$keylist = \@pkeys;
	}

	my $cnt = 0;
	my $com;
	my $event_name;
	my $cevent_name;
	if ($mode eq 'delete') {
		# 削除
		$event_name  = 'ARTICLES_DELETE';
		$cevent_name = 'COMMENTS_DELETE';

		$DB->delete_match("${blogid}_tagart", 'a_pkey', $keylist);
		# $DB->delete_match("${blogid}_rev", 'a_pkey', $keylist);
		$com = $DB->delete_match("${blogid}_com", 'a_pkey', $keylist);
		$cnt = $DB->delete_match("${blogid}_art", 'pkey', $keylist);

	} elsif ($mode eq 'tagset') {
		# タグの追加
		$event_name = 'ARTICLES_EDIT';
		my $append = $opt->{tag_append};
		my $arts = $DB->select_match("${blogid}_art", 'pkey', $keylist, '*cols', ['pkey', 'enable', 'tags'] );

		$DB->begin();
		foreach(@$arts) {
			my $pkey = $_->{pkey};
			my $t = ($append ? $_->{tags} . ',' : '') . $opt->{tags};
			my @tag  = $self->normalize_tag( $t );
			my $tags = join(",",@tag);
			my $r = $DB->update_match("${blogid}_art", { tags => $tags }, 'pkey', $pkey);
			if (!$r) { next; }
			
			# タグ情報書き換え
			$cnt += 1;
			$DB->delete_match("${blogid}_tagart", 'a_pkey', $pkey);
			my $t_pkeys = $self->regist_tags($blogid, \@tag);
			foreach my $t_pkey (@$t_pkeys) {
				$DB->insert("${blogid}_tagart", {
					'a_pkey'   => $pkey,
					'a_enable' => $_->{enable},
					't_pkey'   => $t_pkey
				});
			}
		}
		$DB->commit();

	} elsif ($mode eq 'enable') {
		# 表示に設定
		$event_name = 'ARTICLES_EDIT';
		$cnt = $DB->update_match("${blogid}_art",
			{ enable => 1 },
			'enable', 0,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist
		);
		$DB->update_match("${blogid}_tagart", {
			'a_enable' => 1
		}, 'a_pkey', $keylist);

	} else {
		# 非表示に設定
		$event_name  = 'ARTICLES_EDIT';
		$cevent_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("${blogid}_art",
			{ enable => 0 },
			'enable', 1,
			'-tm', '',	# 下書き記事は対象外
			'pkey', $keylist
		);
		$DB->update_match("${blogid}_tagart", {
			'a_enable' => 0
		}, 'a_pkey', $keylist);

		# 非公開にした記事にコメントがあれば
		my $ary = $DB->select_match("${blogid}_art",
			'enable', 0,
			'-coms', 0,	# 公開コメントがある
			'pkey', $keylist,
			'*cols', ['pkey']
		);
		my @pkeys = map { $_->{pkey} } @$ary;
		if (@pkeys) {
			$com = $DB->update_match("${blogid}_com",
				{ enable => 0 },
				'enable',  1,
				'a_pkey', \@pkeys
			);
		}
	}

	# イベント処理
	if ($cnt) {
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            $keylist, $cnt);
		$self->call_event('ARTICLE_STATE_CHANGE', $keylist);
		if ($com) {
			$self->call_event($cevent_name,           $keylist);
			$self->call_event('COMMENT_STATE_CHANGE', $keylist);
		}
		$self->call_event('ARTCOM_STATE_CHANGE',  $keylist);
	}

	return wantarray ? (0, $cnt) : 0;
}

#-------------------------------------------------------------------------------
# ●コメントの表示状態変更、または削除
#-------------------------------------------------------------------------------
sub edit_comment {
	my ($self, $mode, $keylist) = @_;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};
	if (! $self->{allow_edit}) { $ROBJ->message('Operation not permitted'); return 5; }

	if (ref($keylist) ne 'ARRAY' || !@$keylist) {
		return (0,0);
	}
	$keylist = [ map { int($_) } @$keylist ];

	# 該当する記事のリスト
	my $ary = $DB->select_by_group("${blogid}_com",{
		group_by => 'a_pkey',
		match => { pkey => $keylist }
	});
	my @a_pkeys = map { $_->{a_pkey} } @$ary;

	# 削除
	my $cnt;
	my $event_name;
	if ($mode eq 'delete') {
		$event_name = 'COMMENTS_DELETE';
		$cnt = $DB->delete_match("${blogid}_com", 'pkey', $keylist);

	} elsif ($mode eq 'enable') {
		$event_name = 'COMMENTS_EDIT';

		# 非公開記事のコメントは公開しない
		my $ary = $DB->select_match("${blogid}_art", 
			'pkey', \@a_pkeys,
			'*cols', ['pkey', 'enable']
		);
		my @exlist;
		foreach(@$ary) {
			if ($_->{enable}) { next; }
			push(@exlist, $_->{pkey});
		}
		$cnt = $DB->update_match("${blogid}_com",
			{ enable => 1 },
			'enable', 0,
			'hidden', 0,
			'pkey', $keylist,
			'-a_pkey', \@exlist	# not match
		);
	} else {
		$event_name = 'COMMENTS_EDIT';
		$cnt = $DB->update_match("${blogid}_com",
			{ enable => 0 },
			'enable',  1,
			'pkey', $keylist
		);
	}

	# イベント処理
	if ($cnt) {
		foreach( @a_pkeys ) {
			$self->calc_comments($blogid, $_);
		}
		$keylist = ref($keylist) ? $keylist : [$keylist];
		$self->call_event($event_name,            \@a_pkeys, $keylist, $cnt);
		$self->call_event('COMMENT_STATE_CHANGE', \@a_pkeys, $keylist);
		$self->call_event('ARTCOM_STATE_CHANGE',  \@a_pkeys, $keylist);
	}

	return wantarray ? (0, $cnt) : 0;
}

################################################################################
# ■タグの編集処理
################################################################################
#-------------------------------------------------------------------------------
# ●タグの編集
#-------------------------------------------------------------------------------
sub tag_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	my $joins = $form->{join_ary} || [];
	my $dels  = $form->{del_ary}  || [];
	my $edits = $form->{tag_ary};

	# タグリスト
	my @tags;
	{
		my $ary = $DB->select_match("${blogid}_tag");
		foreach(@$ary) {
			$tags[ $_->{pkey} ] = $_;
		}
	}

	my %e_art;	# 編集したarticleのpkey
	# 中で e_art を参照しているので順番を逆にしてはいけない。
	foreach(@$joins) {
		my ($master, @slaves) = split(',',$_);
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', \@slaves, '*cols', ['a_pkey', 'a_enable'] );
		$DB->delete_match("${blogid}_tagart", 't_pkey', \@slaves);
		$DB->delete_match("${blogid}_tag",    'pkey'  , \@slaves);
		foreach(@$ta) {
			if ($e_art{ $_->{a_pkey} }) { next; }
			my $r = $DB->insert("${blogid}_tagart", {
				a_pkey => $_->{a_pkey},
				t_pkey => $master,
				a_enable => $_->{a_enable}
			});
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの削除
	if(@$dels) {
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $dels, '*cols', 'a_pkey' );
		$DB->delete_match("${blogid}_tagart", 't_pkey', $dels);
		$DB->delete_match("${blogid}_tag"   ,   'pkey', $dels);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}
	# タグの編集
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$name) = split(',',$_,4);
		$ROBJ->normalize_string($name);
		$ROBJ->tag_escape_amp($name);
		if ($name =~ /::/ || $name =~ /,/ || $name eq '') {
			$ROBJ->message("Tag name error '%s'", $name);
			next;
		}
		if($upnode) {
			$name = $tags[ $upnode ]->{name} . '::' . $name;
		}
		my $org = $tags[ $pkey ];
		my $ef_art;
		if ($upnode != $org->{upnode} || $name ne $org->{name}) {
			$ef_art = 1;	# 記事に影響あり
		} elsif ($priority == $org->{priority}) {
			next;		# 変更なし
		}
		my %h = (
			upnode   => ($upnode==0 ? undef : $upnode),
			priority => $priority,
			name     => $name
		);
		my $r = $DB->update_match("${blogid}_tag", \%h, 'pkey', $pkey);
		if (!$r) {	# 失敗
			if ($name ne $org->{name}) {
				$ROBJ->message("Tag edit error '%s' to '%s' (same tag name exist?)", $org->{name}, $name);
			} else {
				$ROBJ->message("Tag edit error '%s'", $org->{name});
			}
			next;
		}

		$h{pkey} = $pkey;
		$tags[ $pkey ] = \%h;

		# 記事の変更予約処理
		if (!$ef_art) { next; }
		my $ta = $DB->select_match("${blogid}_tagart", 't_pkey', $pkey);
		foreach(@$ta) {
			$e_art{ $_->{a_pkey} } = 1;
		}
	}

	# 変更があったarticleのタグ情報を書き換える
	foreach my $a_pkey (keys(%e_art)) {
		my $ta = $DB->select_match("${blogid}_tagart", 'a_pkey', $a_pkey, '*cols', 't_pkey');
		my @t_pkeys = map { $_->{t_pkey} } @$ta;

		# upnodeのいずれかのタグを含まないかチェック
		my %h;
		foreach(@t_pkeys) {
			my $up = $tags[$_]->{upnode};
			while($up) {
				$h{$up} = 1;
				$up = $tags[$up]->{upnode};
			}
		}
		my @tag;
		my @dels;
		foreach(@t_pkeys) {
			if ($h{$_}) {
				push(@dels, $_);
				next;
			}
			push(@tag, $tags[ $_ ]->{name});
		}
		# ツリー組み換えにより重複したタグを削除
		$DB->delete_match("${blogid}_tagart", 'a_pkey', $a_pkey, 't_pkey', \@dels);

		# 新しいタグ情報に書き換え
		my $tag = join(',', @tag);
		$DB->update_match("${blogid}_art", {tags => $tag}, 'pkey', $a_pkey);
	}
	if (%e_art) {
		my $artkeys = keys(%e_art);
		$self->call_event('ARTICLE_STATE_CHANGE', $artkeys);
	}
	$self->update_taglist();

	return 0;
}

################################################################################
# ■コンテンツの編集処理
################################################################################
#-------------------------------------------------------------------------------
# ●コンテンツの編集
#-------------------------------------------------------------------------------
sub contents_edit {
	my $self = shift;
	my $form = shift;
	my $ROBJ = $self->{ROBJ};
	my $DB   = $self->{DB};
	my $blogid = $self->{blogid};

	# タグリスト
	my %cons;
	{
		my $ary = $DB->select_match("${blogid}_art",
			'enable', 1,
			'-ctype', '',
			'*cols', ['pkey', 'title', 'link_key', 'priority', 'upnode', 'coms_all']
		);
		%cons = map { $_->{pkey} => $_ } @$ary;
	}

	# タグの編集
	my $edits = $form->{contents_txt_ary};
	my $com_edit;
	foreach(@$edits) {
		my ($pkey,$upnode,$priority,$link_key) = split(',',$_,4);
		$ROBJ->normalize_string($link_key);
		if ($link_key =~ /^[\"\',]/ || $link_key =~ /^\s*$/ || $link_key =~ m|^[\d&]|) {
			$link_key = '';
		}
		my $org = $cons{ $pkey };
		my %h;
		if ($upnode != $org->{upnode} && ($cons{$upnode} || $upnode==0)) {
			$h{upnode} = $upnode;
		}
		if ($link_key ne '' && $link_key ne $org->{link_key}) {
			$h{link_key} = $link_key;
		}
		if ($priority != $org->{priority}) {
			$h{priority} = $priority;
		}
		if (!%h) { next; }

		$DB->update_match("${blogid}_art", \%h, 'pkey', $pkey);
		if (exists($h{link_key}) && $cons{$pkey}->{coms_all}) {
			my $elkey = $h{link_key};
			$self->link_key_encode($elkey);
			my $r = $DB->update_match("${blogid}_com", { a_elink_key=>$elkey }, 'a_pkey', $pkey);
			if ($r) { $com_edit=1; }
		}
	}

	# イベント処理
	my $a_pkeys = keys(%cons);
	$self->call_event('ARTICLE_STATE_CHANGE', $a_pkeys);
	if ($com_edit) {
		$self->call_event('COMMENT_STATE_CHANGE', $a_pkeys);
	}
	$self->call_event('ARTCOM_STATE_CHANGE', $a_pkeys);

	return 0;
}


1;
