# allow to set pps

defmodule ClientTest do
  # 95.217.38.33
  #def start(remote_address \\ {{127, 0, 0, 1}, 9090}) do
  #pid = ClientTest.start {{116, 202, 246, 77}, 9090}
  def start(remote_address \\ {{95, 217, 38, 33}, 9090}) do
    pid = spawn_link(__MODULE__, :receiver, [remote_address])
  end

  def receiver(remote_address) do
    {:ok, sock} =
      :gen_udp.open(0, [
        :binary,
        {:active, false}
      ])

    IO.inspect(:inet.port(sock))

    Process.send_after(self(), :timer, 1000)

    receiver(sock, %{
      packets: 2,
      delay: 1,
      packets_size: 1024,
      remote_address: remote_address,
      last_seqs: [],
      series: []
    })
  end

  def receiver(sock, state) do
    res = :gen_udp.recv(sock, 4096, 25)

    state =
      case res do
        {:ok, {_ip, _port, <<seqid::64-little, packet::binary>>}} ->
          # count seq number

	  IO.inspect byte_size(packet)
          # IO.inspect res 
          Map.put(state, :last_seqs, [seqid | state.last_seqs])

        _ ->
          state
      end

    state =
      receive do
        {:update, packets, delay, packets_size} ->
          %{state | packets: packets, delay: delay, packets_size: packets_size}

        :timer ->
          Process.send_after(self(), :timer, 1000)

          :gen_udp.send(sock, state.remote_address, 0, <<
            state.packets::32-little,
            state.delay::32-little,
            state.packets_size::32-little
          >>)

          series = [Enum.count(state.last_seqs) | state.series]
          IO.inspect({:series, hd(series), state.packets, state.delay, state.packets_size})
          %{state | last_seqs: [], series: series}
      after
        0 ->
          state
      end

    __MODULE__.receiver(sock, state)
  end
end

defmodule ServerTest do
  def start(port) do
    pid = spawn_link(__MODULE__, :receiver, [port])
  end

  def receiver(port) do
    {:ok, sock} =
      :gen_udp.open(port, [
        :binary,
        {:active, true}
      ])

    IO.inspect(:inet.port(sock))

    Process.send_after(self(), :timer, 1000)

    receiver(sock, %{
      channels: []
    })
  end

  def proc_data(
        ip,
        port,
        <<
          packets::32-little,
          delay::32-little,
          packets_size::32-little
        >>,
        state
      ) do
    chan =
      Enum.find(state.channels, fn chan ->
        chan.remote_host == {ip, port}
      end)

    if chan == nil do
      IO.inspect("should start channel #{inspect({ip, port})}")

      nsender = Sender.start({ip, port}, delay, packets)

      nchan = %{
        remote_host: {ip, port},
        packets: packets,
        delay: delay,
        packets_size: packets_size,
        pid: nsender
      }

      %{
        state
        | channels: [nchan | state.channels]
      }
    else
      send(chan.pid, {:update, packets, delay, packets_size})
      state
    end
  end

  def proc_data(_ip, _port, _, state) do
    state
  end

  def receiver(sock, state) do
    state =
      receive do
        {:udp, socket, ip, port, data} ->
          proc_data(ip, port, data, state)

        :timer ->
          Process.send_after(self(), :timer, 1000)
          state
      after
        5000 ->
          state
      end

    __MODULE__.receiver(sock, state)
  end
end

defmodule Sender do
  def start(remote_host, delay, packets) do
    pid = spawn_link(__MODULE__, :receiver, [remote_host, delay, packets])
  end

  def receiver(remote_host, delay, packets) do
    {:ok, sock} =
      :gen_udp.open(0, [
        :binary,
        {:active, false}
      ])

    IO.inspect(:inet.port(sock))

    {host, port} =remote_host 
    sender(sock, %{
      remote_host: remote_host,
      host: host,
      port: port,
      delay: delay,
      packets: packets,
      packets_size: 1024,
      counter: 0
    })
  end

  def sender(sock, state) do
    
    Enum.each(1..state.packets, fn x ->
      # IO.inspect "sending"
      bin = Process.get {:packet, state.packets_size}
      bin = if bin == nil do
      dat = :binary.copy(<<0>>, state.packets_size - 8)
        Process.put {:packet, state.packets_size}, dat
	dat
	else
	bin
	end

      :gen_udp.send(sock, state.host, state.port, bin)
    end)

    :timer.sleep(state.delay)

    state =
      receive do
        {:update, packets, delay, packets_size} ->
          %{
            state
            | delay: delay,
              packets: packets,
	      packets_size: packets_size
          }
      after
        0 ->
          state
      end

    __MODULE__.sender(sock, state)
  end
end
