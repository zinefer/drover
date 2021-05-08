# 📺🐕 drOVER

drOVER is a set of bash scripts that assist in downloading a very specific video stream.

Uses the [Taskfile](https://github.com/adriancooney/Taskfile) pattern.

## Install Dependencies

- Install golang

```
task install
```

## List new episodes

```
task new --quiet
```

## Download new episodes

```
task download-new
```

## Metadata

These scripts will attempt to save the episode plot to a metadata file only supported by [Extended Personal Media Scanner](https://bitbucket.org/mjarends/plex-scanners/src/master/).