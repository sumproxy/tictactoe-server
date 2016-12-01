## How to create your own copy of Tic-tac-toe server

Follow the instructions below to create your own game server

1. Download [heroku command line](https://devcenter.heroku.com/articles/heroku-cli). 
Make sure to verify your installation and login (create your credentials first).

    ```
    heroku login
    ```

2. Clone the server's repository

    ```
    git clone https://github.com/sumproxy/tictactoe-server.git <your_local_folder_name>
    cd <your_local_folder_name>
    heroku create
    ```
Here heroku will create your own copy of server application in Heroku's repository and print to console its address (check instructions on [Heroku](https://devcenter.heroku.com/) if you want a specific name for your server) something like `https://peaceful-shore-62816.herokuapp.com`

3. Push the code of Tic-tac-toe server to heroku repository you just created

    ```
    git push heroku master
    ```

4. Make sure to update the client's address https://github.com/sumproxy/tictactoe/blob/master/src/main.rs#L63 and you can play the game using your own server.
