require Logger

defmodule ExSync.BeamMonitor do
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) when is_list(opts) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: ExSync.Config.beam_dirs())
    FileSystem.subscribe(watcher_pid)

    {:ok, %{watcher_pid: watcher_pid, finished_reloading_timer: false}}
  end

  def handle_info({:file_event, watcher_pid, {path, events}}, state) do
    dump =
      if path === "/home/niahoo/src/pheral/_build/dev/lib/pheral/ebin/cowboy_pheral_fcgi.beam" do
        # fn log -> IO.puts(log) end
        fn _ -> :ok end
      else
        fn _ -> :ok end
      end
    dump.("file_event: #{path} : #{inspect events}")
    %{watcher_pid: watcher_pid, finished_reloading_timer: finished_reloading_timer} = state

    if finished_reloading_timer do
      Process.cancel_timer(finished_reloading_timer)
    end


    if Path.extname(path) in [".beam"] do
      {:created in events, :removed in events, :modified in events, File.exists?(path)}
      |> case do
        # update
        {_, _, true, true} ->
        dump.("reload #{path}")
          # At least on linux platform, we're seeing a :modified event followed by a
          # :modified, closed event.  By ensuring the modified event arrives on its own,
          # we should be ablle to ensure we reload only once in a cross-platorm friendly way.
          # Note: TODO I don't have a Mac or Windows env to verify this!
          if [:modified] == events do
            Logger.debug "reload module #{Path.basename(path, ".beam")}"
            ExSync.Utils.reload path
          end

        # temp file
        {true, true, _, false} ->
          dump.("tempfile #{path}")
          nil

        # remove
        {_, true, _, false} ->
          dump.("unload #{path}")
          Logger.debug("unload module #{Path.basename(path, ".beam")}")
          ExSync.Utils.unload(path)

        {true, false, false, true} ->
          Logger.debug "reload module #{Path.basename(path, ".beam")}"
          ExSync.Utils.reload path

        # create
        other ->
          dump.("create OTHER #{path}\n#{inspect other}")
          nil
      end
    end

    reload_timeout = ExSync.Config.reload_timeout()
    timer_ref = Process.send_after(self(), :reload_complete, reload_timeout)

    {:noreply, %{state | finished_reloading_timer: timer_ref}}
  end

  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    Logger.debug("ExSync beam monitor stopped.")
    {:noreply, state}
  end

  def handle_info(:reload_complete, state) do
    Logger.debug("ExSync reload complete!")
    if callback = ExSync.Config.reload_callback() do
      {mod, fun, args} = callback
      Task.start(mod, fun, args)
    end

    {:noreply, state}
  end
end
