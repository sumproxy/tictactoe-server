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
        s.player
          .take(2)
          .map{|p| p.first.socket }
          .include? ws
      end
    end
  end

  def add_session(session)
    @sessions << session
    delete_clients(session.player.take(2))
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
    @socket.send({ "next"=> last_move }.to_json)
  end
end

class Session
  attr :player, :current, :board, :count

  def initialize(players)
    @player = players.zip(["x", "o"]).cycle
    @board = [[" ", " ", " "], [" ", " ", " "], [" ", " ", " "]]
    @count = 0
    @current = @player.next
    @current.first.get_move([])
  end

  def process_move(y, x)
    coords = [0, 1, 2]
    if coords.include?(x) && coords.include?(y)
      if @board[y][x] == " "
        @board[y][x] = @current.last
        winner = self.winner(y, x)
        self.gameover?(winner)
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

  def gameover?(winner)
    winner == " " && @count > 8
    when "x", "o"
    end
  end

  def winner(y, x)
    let player = board[y][x];

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
    when [0, 1], [1, 0], [1, 2], [2, 1] then " "
    else
      # on a primary diagonal
      if y == x && board[0][0] == player && board[1][1] == player && board[2][2] == player
        player
      # on a secondary diagonal
      elsif y + x == 2 && board[0][2] == player && board[1][1] == player && board[2][0] == player
        player
      # everything else
      else
        " "
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
      p [:message, ws.object_id]
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

        if state.clients.detect{|c| c.rival == json['rival'] }
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
        elsif state.clients.detect{|c| c.rival.nil? }
          rival = state.clients.detect{|c| c.rival.nil? }
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
      # TODO to test the deletion of the socket from sessions
      state.clients.delete(ws)
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
