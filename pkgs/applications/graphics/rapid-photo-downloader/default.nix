{ stdenv, fetchurl, python3Packages
, file, intltool, gobjectIntrospection, libgudev
, udisks, glib, gnome3, gst_all_1, libnotify
, exiv2, exiftool, qt5, gdk_pixbuf
}:

python3Packages.buildPythonApplication rec {
  pname = "rapid-photo-downloader";
  version = "0.9.12";

  src = fetchurl {
    url = "https://launchpad.net/rapid/pyqt/${version}/+download/${pname}-${version}.tar.gz";
    sha256 = "0nzahps7hs120xv2r55k293kialf83nx44x3jg85yh349rpqrii8";
  };

  # Disable version check and fix install tests
  postPatch = ''
    substituteInPlace raphodo/constants.py \
      --replace "disable_version_check = False" "disable_version_check = True"
    substituteInPlace raphodo/rescan.py \
      --replace "from preferences" "from raphodo.preferences"
    substituteInPlace raphodo/copyfiles.py \
      --replace "import problemnotification" "import raphodo.problemnotification"
  '';

  nativeBuildInputs = [ file intltool gobjectIntrospection ];

  buildInputs = [
    libgudev
    udisks
    glib
    gnome3.gexiv2
    gst_all_1.gstreamer
    libnotify
    exiv2
    exiftool
    qt5.qtimageformats
    gdk_pixbuf
  ] ++ (with python3Packages; [
    pyqt5
    pygobject3
    gphoto2
    pyzmq
    tornado
    psutil
    pyxdg
    arrow
    dateutil
    easygui
    colour
    pymediainfo
    sortedcontainers
    rawkit
    requests
    colorlog
    pyprind
  ]);

  makeWrapperArgs = [
    "--set GI_TYPELIB_PATH \"$GI_TYPELIB_PATH\""
    "--set PYTHONPATH \"$PYTHONPATH\""
  ];

  meta = with stdenv.lib; {
    description = "Photo and video importer for cameras, phones, and memory cards";
    homepage = http://www.damonlynch.net/rapid/;
    license = licenses.gpl3;
    platforms = platforms.linux;
    maintainers = with maintainers; [ jfrankenau ];
  };
}
