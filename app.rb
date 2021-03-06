require 'faye/websocket'
require 'json'

class State
  attr :clients, :sessions
  def initialize
    @clients, @sessions = [], []
  end

  def find_session(ws)
    unless self.sessions.empty?
      self.sessions.detect do |s|
        s.current.first.socket == ws
      end
    end
  end

  def add_session(session)
    @sessions << session
    delete_clients(session.player.take(2))
  end

  def terminate_session(ws)
    session = self.sessions.detect{|s| s.player.take(2).any?{|p| p.first.socket == ws } }
    if session
      p [:terminate_session, session.object_id]
      session.close_sockets
      self.sessions.delete(session)
    end
  end

  def delete_clients(clients)
    clients.each{|c| self.clients.delete(c) }
  end
end

class Player
  attr :socket, :id, :rival

  def initialize(id, ws, rival)
    @socket = ws
    @id = id
    @rival = rival
  end

  def get_move(last_move)
    @socket.send({ "gameover" => "false", "last_move" => last_move }.to_json)
  end

  def gameover(result, move)
    @socket.send({ "gameover" => result, "last_move" => move }.to_json)
  end
end

class Session
  attr :player, :current, :board, :count

  def initialize(players)
    @player = players.zip([:X, :O]).cycle
    common_setup
  end

  def reset
    @player.next until @player.peek.last == :X
    common_setup
  end

  private def common_setup
    @board = Array.new(3) { Array.new(3) { nil } }
    @count = 0
    @current = @player.next
    @current.first.get_move([-1])
  end

  private def gameover?(winner, move)
    if (winner == nil && @count == 8)
      @current.first.gameover("draw", move)
      @player.peek.first.gameover("draw", move)
      exchange_player_faces if rand(2) == 1
      self.reset
      return true
    elsif [:X, :O].include? winner
      @current.first.gameover("won", move)
      @player.peek.first.gameover("lost", move)
      exchange_player_faces if winner == :O
      self.reset
      return true
    end

    false
  end

  private def exchange_player_faces
    p1, p2 = @player.take(2)
    p [:players, :p1, p1.first.socket.object_id, :p2, p2.first.socket.object_id]
    if p1.last == :O
      @player = [p1.first, p2.first].zip([:X, :O]).cycle
    else
      @player = [p2.first, p1.first].zip([:X, :O]).cycle
    end
  end

  def process_move(y, x)
    coords = [0, 1, 2]
    if coords.include?(x) && coords.include?(y)
      if @board[y][x] == nil
        @board[y][x] = @current.last
        winner = self.winner(y, x)
        if gameover?(winner, [y, x])
          p [:gameover, "#{winner} wins"]
          return 
        end
        @current = @player.next
        @count += 1
        @current.first.get_move([y, x])
        p [:move, @count, [y, x], @board]
      else
        @current.first.socket.send({ "error" => "Board position already taken" }.to_json)
      end
    else
      @current.first.socket.send({ "error" => "Move coords are invalid" }.to_json)
    end
  end

  def winner(y, x)
    player = board[y][x];

    # check row
    if board[y][0] == player && board[y][1] == player && board[y][2] == player
      return player
    end

    # check column
    if board[0][x] == player && board[1][x] == player && board[2][x] == player
      return player
    end

    case [y, x]
    # not on a diagonal
    when [0, 1], [1, 0], [1, 2], [2, 1] then nil
    else
      # on a primary diagonal
      if y == x && board[0][0] == player && board[1][1] == player && board[2][2] == player
        player
      # on a secondary diagonal
      elsif y + x == 2 && board[0][2] == player && board[1][1] == player && board[2][0] == player
        player
      # everything else
      else
        nil
      end
    end
  end

  def close_sockets
    p [:session_close_sockets, self.object_id]
    sockets = self.player.take(2).map{|p| p.first.socket }
    sockets.each do |ws|
      if ws
        ws.send({"gameover" => "quit", "last_move" => []}.to_json)
        p [:closing, ws.object_id]
        ws.close
      end
    end
  end
end

def parse(msg)
  json = JSON.parse(msg)
  p [:json, json]
  json
rescue JSON::ParserError => e
  p [:error, e]
end

state = State.new

App = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env, nil, {:ping => 5})

    ws.on :open do |event|
      p [:open, ws.object_id]
    end

    ws.on :message do |event|
      p [:message, ws.object_id, event.data]
      json = parse(event.data)

      session = state.find_session(ws)
      p [:session_found, session.object_id]

      if session && json['move']
        p [:move, json['move']]
        session.process_move(*json['move'])
        next
      end

      if json['message'] == 'connect'
        if state.clients.detect{|c| c.id == json['id'] }
          p [:error, "id #{json['id']} exists and active"]
          ws.send({ "error" => "id exists and active" }.to_json)
          next
        end

        if state.clients.detect{|c| c.rival == json['rival'] && !c.rival.empty? }
          p [:error, "rival #{json['id']} is already expected by someone"]
          ws.send({ "error" => "rival is already expected by someone" }.to_json)
          next
        end

        player = Player.new(json['id'], ws, json['rival'])
        rival = state.clients.detect{|c| c.rival == json['id'] }

        if rival
          session = Session.new([player, rival])
          state.add_session(session)
          p [:session_created, session.object_id]
        elsif state.clients.detect{|c| c.rival.empty? }
          rival = state.clients.detect{|c| c.rival.empty? }
          session = Session.new([rival, player])
          state.add_session(session)
          p [:session_created, session.object_id]
        else
          state.clients << player
          p [:message, "Player #{player.id} added to queue"]
          ws.send({ "ok" => "Player added to queue" }.to_json)
        end
      end
    end

    ws.on :close do |event|
      p [:close, ws.object_id, event.code, event.reason]
      state.clients.delete_if{|c| c.socket == ws }
      state.terminate_session(ws)
      ws = nil
    end

    ws.on :error do |event|
      p [:error, ws.object_id, event.code, event.reason]
    end

    # Return async Rack response
    ws.rack_response

  else
    # Normal HTTP request
    [200, {'Content-Type' => 'text/plain'}, ['Please use a websocket connection']]
  end
end
