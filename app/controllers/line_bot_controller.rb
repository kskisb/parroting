class LineBotController < ApplicationController
  def health
    render json: { status: 'ok' }, status: :ok
  end

  def callback
    body = request.body.read
    events = client.parse_events_from(body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Location
          sendRestInfo(client, event)
        else
          message = {
            type: "text",
            text: "左側の＋ボタンからレストランを検索したい場所の位置情報を送信してください。"
          }
          client.reply_message(event['replyToken'], message)
        end
      end
    end
  end

  private

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def sendRestInfo(client, event)
    lat = event.message['latitude']
    lng = event.message['longitude']
    reply_msg = getRestInfo(lat, lng)

    message = {
      type: "template",
      altText: "レストラン一覧",
      template: {
        type: "carousel",
        columns: reply_msg,
        imageAspectRatio: "rectangle",
        imageSize: "cover"
      }
    }

    response = client.reply_message(event['replyToken'], message)
  end

  def getRestInfo(lat, lng)
    apikey = ENV["GOOGLE_MAPS_API_KEY"]
    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=#{lat},#{lng}&radius=1500&type=restaurant&key=#{apikey}&language=ja"

    uri = URI(url)
    response = Net::HTTP.get(uri)

    data = JSON.parse(response)

    data["results"].each do |result|
      # 店のurlを取得
      result["url"] = getURL(result["place_id"])

      # 評価順に並べ替えるための重み付け
      result["rating"] = (result["rating"].to_f ** 2.5) * (result["user_ratings_total"].to_f ** 0.25)
    end

    # 評価順に並べ替え
    sorted_results = data["results"].sort_by { |result| -result["rating"] }

    columns = []
    sorted_results.first(10).each do |shop|
      addr = shop["vicinity"]
      add = add[0, 40] if addr.length > 40

      column = {
        title: shop["name"],
        text: addr,
        actions: [
          {
            type: "uri",
            label: "Google Mapで開く",
            uri: shop["url"]
          }
        ]
      }
      columns << column
    end
    columns
  end

  def getURL(place_id)
    apikey = ENV["GOOGLE_MAPS_API_KEY"]
    url = "https://maps.googleapis.com/maps/api/place/details/json?place_id=#{place_id}&fields=url&key=#{apikey}"

    # http GET リクエストを送信
    uri = URI(url)
    response = Net::HTTP.get(uri)

    # JSONデコード
    result = JSON.parse(response)

    # URLを検出
    return result["status"] == "OK" ? result["result"]["url"] : nil
  end
end
