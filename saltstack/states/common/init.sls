update_pkgs:
  pkg.uptodate:
    - refresh: True

common_packages:
  pkg.installed:
    - pkgs:
      - curl
      - vim-tiny
