{ lib, fetchurl, stdenv, ncurses,
IOKit, python }:

stdenv.mkDerivation rec {
  name = "htop-${version}";
  version = "2.2.0";

  src = fetchurl {
    url = "https://hisham.hm/htop/releases/${version}/${name}.tar.gz";
    sha256 = "0mrwpb3cpn3ai7ar33m31yklj64c3pp576vh1naqff6f21pq5mnr";
  };

  nativeBuildInputs = [ python ];
  buildInputs =
    [ ncurses ] ++
    lib.optionals stdenv.isDarwin [ IOKit ];

  prePatch = ''
    patchShebangs scripts/MakeHeader.py
  '';

  meta = with stdenv.lib; {
    description = "An interactive process viewer for Linux";
    homepage = https://hisham.hm/htop/;
    license = licenses.gpl2Plus;
    platforms = with platforms; linux ++ freebsd ++ openbsd ++ darwin;
    maintainers = with maintainers; [ rob relrod ];
  };
}
