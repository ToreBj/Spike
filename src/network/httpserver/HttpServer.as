package network.httpserver
{
    import flash.events.Event;
    import flash.events.ProgressEvent;
    import flash.events.ServerSocketConnectEvent;
    import flash.net.ServerSocket;
    import flash.net.Socket;
    import flash.net.URLVariables;
    import flash.utils.ByteArray;
    import flash.utils.clearInterval;
    import flash.utils.setTimeout;
    
    import model.ModelLocator;
    
    import ui.popups.AlertManager;
    
    import utils.Trace;
	
	[ResourceBundle("loopservice")]
	
    public class HttpServer
    {
		/* Constants */
		private static const MAX_CONNECTION_ATTEMPTS:uint = 20;
		
        private var _serverSocket:ServerSocket;
        private var _controllers:Object = new Object();
        private var _isConnected:Boolean = false;
		private var _connectionRetries:int = 0;
		private var _timeoutID:int = -1;
        
        public function HttpServer() {}

        
        public function get isConnected():Boolean
        {
            return _isConnected;
        }
        
        /**
        * Begin listening on a specified port.
        * 
        * @param port The localhost port to begin listening on.
        */
        public function listen(port:int):void
        {   
			//Clear previous connection retry
			if( _timeoutID != -1 ) 
				clearInterval( _timeoutID );
			
			//Connect server
            try
            {
                _serverSocket = new ServerSocket();
                _serverSocket.addEventListener(Event.CONNECT, socketConnectHandler);
				_serverSocket.addEventListener(Event.CLOSE, close);
                _serverSocket.bind(port);
                _serverSocket.listen();
            }
            catch (error:Error)
            {
				_isConnected = false;
				
				if (_connectionRetries < MAX_CONNECTION_ATTEMPTS)
				{
					_connectionRetries++;
					_timeoutID = setTimeout( listen, 5000, port );
					
					Trace.myTrace("HttpServer.as", "Server error! Retrying connection in 5 seconds. Reconnection attempt: " + _connectionRetries);
				}
				else
				{
					Trace.myTrace("HttpServer.as", "Server error! Can't bind to port: " + port + ". Notifying user...");
					
					var message:String = ModelLocator.resourceManagerInstance.getString('loopservice','error_alert_mesage').replace("{port}", port.toString()) + " " + error.message;
					
					AlertManager.showSimpleAlert(ModelLocator.resourceManagerInstance.getString('loopservice','error_alert_title'), message);
				}
            }
			
			Trace.myTrace("HttpServer.as", "Connection successful!");
			
			_isConnected = true;
        }
		
		/**
		 * Close Server
		 */
		public function close(e:Event = null):void
		{
			_serverSocket.removeEventListener(Event.CONNECT, socketConnectHandler);
			_serverSocket.removeEventListener(Event.CLOSE, close);
			
			try
			{
				_serverSocket.close();
				
				for (var i:String in _controllers)
				{
					if (i != null)
						_controllers[i] = null;
				}
			} 
			catch(error:Error){}
			
			_controllers = null;
			_serverSocket = null;
			
			Trace.myTrace("HttpServer.as", "Server closed!");
		}
        
        /**
        * Add a Controller to the Server
         */
        public function registerController(controller:ActionController):HttpServer
        {
            _controllers[controller.route] = controller;
            return this;  
        }
        
        /**
        * Handle new connections to the server.
         */
        private function socketConnectHandler(event:ServerSocketConnectEvent):void
        {
            var socket:Socket = event.socket;
            socket.addEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler, false, 0, true);
        }
        
        /**
        * Handle data written to open connections. This is where the request is
        * parsed and routed to a controller.
         */
        private function socketDataHandler(event:ProgressEvent):void
        {
            try
            {
                var socket:Socket = event.target as Socket;
                var bytes:ByteArray = new ByteArray();

                // Get the request string and pull out the URL 
                socket.readBytes(bytes);
                var request:String          = "" + bytes;
                var url:String              = request.substring(4, request.indexOf("HTTP/") - 1);
                
                // Parse out the controller name, action name and paramert list
                var url_pattern:RegExp      = /(.*)\/([^\?]*)\??(.*)$/;
                var controller_key:String   = url.replace(url_pattern, "$1").replace(" ", "");
                var action_key:String       = url.replace(url_pattern, "$2");
				var param_string:String     = url.replace(url_pattern, "$3");
				param_string = param_string == "" ? null : param_string;
				
				var parameters:URLVariables;
				
				if (request.substring(0, 4).toUpperCase().indexOf("GET") != -1 ) 
				{
					//GET request
					parameters = new URLVariables(param_string);
				}
				else if (request.substring(0, 4).toUpperCase().indexOf("POST") != -1 ) 
				{
					//POST request
					var postJSONResponse:Object = null;
					try
					{
						var messageLines:Array = request.split("\n");
						postJSONResponse = JSON.parse(messageLines[messageLines.length - 1]);
					} 
					catch(error:Error) {}
					
					parameters = objectToURLVariables(postJSONResponse, param_string);
				}
				
				var controller:ActionController = _controllers[controller_key];
                
                if (controller) 
                    socket.writeUTFBytes(controller.doAction(action_key, parameters));
                
				//Discard socket
                socket.flush();
                socket.close();
				socket.removeEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler);
				socket = null;
            }
            catch (error:Error)
            {
                AlertManager.showSimpleAlert(ModelLocator.resourceManagerInstance.getString('loopservice','error_alert_title'), error.message, 30);
            }
        }
		
		private function objectToURLVariables(parameters:Object, variables:String = null):URLVariables
		{
			var paramsToSend:URLVariables;
			if (variables == null)
				paramsToSend = new URLVariables();
			else
				paramsToSend = new URLVariables(variables);
			
			if (parameters != null)
			{
				for (var i:String in parameters)
				{
					if (i != null)
					{
						if (parameters[i] is Array)
							paramsToSend[i] = parameters[i];
						else
							paramsToSend[i] = parameters[i].toString();
					}
				}
			}
			
			return paramsToSend;
		}

		public function get serverSocket():ServerSocket
		{
			return _serverSocket;
		}

    }
}