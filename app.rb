require 'faye/websocket'

App = lambda do |env|
  if Faye::WebSocket.websocket?(env)
    ws = Faye::WebSocket.new(env)
    clients = []

    ws.on :open do |event|
      p [:open, ws.object_id]
      clients << ws
    end

    ws.on :message do |event|
      p [:message, event.data]
      clients.each{|client| client.send(event.data.reverse) }
    end

    ws.on :close do |event|
      p [:close, ws.object_id, event.code, event.reason]
      clients.delete(ws)
      ws = nil
    end

    # Return async Rack response
    ws.rack_response

  else
    # Normal HTTP request
    [200, {'Content-Type' => 'text/plain'}, ['Please use websocket connection']]
  end
end
