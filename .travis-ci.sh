bash -ex .travis-opam.sh
eval $(opam config env)
ocaml_version=$(opam config var ocaml-version)

function build_js () {
    opam install -y js_of_ocaml
    make js
}

case $ocaml_version in
    4.02.3)
        build_js
        ;;
    4.03.0)
        build_js
        ;;
    4.04.0)
        build_js
        ;;
    *)
        echo "Unknown ocaml version: $ocaml_version"
        exit 1
        ;;
esac

make doc
bash -ex .ci-indent.sh
