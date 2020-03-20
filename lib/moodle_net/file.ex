# MoodleNet: Connecting and empowering educators worldwide
# Copyright © 2018-2020 Moodle Pty Ltd <https://moodle.com/moodlenet/>
# Contains code from Pleroma <https://pleroma.social/> and CommonsPub <https://commonspub.org/>
# SPDX-License-Identifier: AGPL-3.0-only

defmodule MoodleNet.File do
  @moduledoc """
  Utilities for working with files.
  """

  @doc """
  Returns true if the given `filepath` contains one of the
  extensions in `allowed_exts`.

  Note that the comparison is case-insensitive.
  """
  @spec has_extension?(binary, [binary]) :: boolean
  def has_extension?(filepath, allowed_exts) do
    allowed_exts
    |> Enum.map(fn ext -> ".#{ext}" end)
    |> Enum.member?(extension(filepath))
  end

  @doc """
  Return the file extension of the given `filepath` in lowercase.
  """
  @spec extension(binary) :: binary
  def extension(filepath) do
    filepath |> Path.extname |> String.downcase
  end

  @doc """
  Return the base name of a full file path without the extension.

  ## Example

  iex> basename("some/path/file.txt")
  "file"
  """
  @spec basename(binary) :: binary
  def basename(filepath) do
    case extension(filepath) do
      ""  -> Path.basename(filepath)
      ext -> Path.basename(filepath, ext)
    end
  end

  # Taken from https://github.com/stavro/arc/blob/master/lib/arc/file.ex
  @doc """
  Generate a path in the OS temporary directory.

  If a file is supplied, the extension of the file name is preserved.
  """
  @spec generate_temporary_path(file :: any) :: binary
  def generate_temporary_path(file \\ nil) do
    extension = extension((file && file.path) || "")

    filename =
      :crypto.strong_rand_bytes(20)
      |> Base.encode32()
      |> Kernel.<>(extension)

    Path.join(System.tmp_dir(), filename)
  end
end
