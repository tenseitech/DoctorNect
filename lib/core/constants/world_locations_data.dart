abstract final class WorldLocationsData {
  static const Map<String, Map<String, List<String>>> byCountry = {
    'Afghanistan': {
      'Kabul Province': ['Kabul', 'Bagrami', 'Paghman'],
      'Herat Province': ['Herat', 'Guzara', 'Injil'],
      'Balkh Province': ['Mazar-i-Sharif', 'Balkh', 'Dehdadi'],
      'Kandahar Province': ['Kandahar', 'Arghandab', 'Daman'],
      'Nangarhar Province': ['Jalalabad', 'Surkh Rod', 'Kama'],
    },
    'Australia': {
      'New South Wales': ['Sydney', 'Newcastle', 'Wollongong', 'Albury'],
      'Victoria': ['Melbourne', 'Geelong', 'Ballarat', 'Bendigo'],
      'Queensland': ['Brisbane', 'Gold Coast', 'Townsville', 'Cairns'],
      'Western Australia': ['Perth', 'Bunbury', 'Geraldton', 'Albany'],
      'South Australia': [
        'Adelaide',
        'Mount Gambier',
        'Whyalla',
        'Murray Bridge'
      ],
      'Tasmania': ['Hobart', 'Launceston', 'Devonport', 'Burnie'],
      'Australian Capital Territory': ['Canberra', 'Belconnen', 'Tuggeranong'],
      'Northern Territory': ['Darwin', 'Alice Springs', 'Palmerston'],
    },
    'Bangladesh': {
      'Dhaka Division': ['Dhaka', 'Gazipur', 'Narayanganj', 'Tangail'],
      'Chattogram Division': ['Chattogram', "Cox's Bazar", 'Comilla', 'Feni'],
      'Rajshahi Division': ['Rajshahi', 'Bogra', 'Pabna', 'Natore'],
      'Khulna Division': ['Khulna', 'Jessore', 'Satkhira', 'Bagerhat'],
      'Sylhet Division': ['Sylhet', 'Moulvibazar', 'Habiganj', 'Sunamganj'],
      'Rangpur Division': ['Rangpur', 'Dinajpur', 'Nilphamari', 'Gaibandha'],
      'Barishal Division': ['Barishal', 'Patuakhali', 'Bhola', 'Jhalokati'],
      'Mymensingh Division': ['Mymensingh', 'Jamalpur', 'Netrokona', 'Sherpur'],
    },
    'Bhutan': {
      'Thimphu District': ['Thimphu', 'Dechencholing', 'Babesa'],
      'Paro District': ['Paro', 'Shaba', 'Dopshari'],
      'Punakha District': ['Punakha', 'Khuruthang', 'Wangdue Phodrang'],
    },
    'Canada': {
      'Ontario': ['Toronto', 'Ottawa', 'Mississauga', 'Hamilton'],
      'Quebec': ['Montreal', 'Quebec City', 'Laval', 'Gatineau'],
      'British Columbia': ['Vancouver', 'Surrey', 'Burnaby', 'Victoria'],
      'Alberta': ['Calgary', 'Edmonton', 'Red Deer', 'Lethbridge'],
      'Manitoba': ['Winnipeg', 'Brandon', 'Steinbach', 'Thompson'],
      'Saskatchewan': ['Saskatoon', 'Regina', 'Prince Albert', 'Moose Jaw'],
      'Nova Scotia': ['Halifax', 'Sydney', 'Truro', 'New Glasgow'],
    },
    'China': {
      'Beijing Municipality': ['Beijing', 'Tongzhou', 'Changping', 'Shunyi'],
      'Shanghai Municipality': ['Shanghai', 'Pudong', 'Minhang', 'Jiading'],
      'Guangdong': ['Guangzhou', 'Shenzhen', 'Dongguan', 'Foshan'],
      'Zhejiang': ['Hangzhou', 'Ningbo', 'Wenzhou', 'Jiaxing'],
      'Sichuan': ['Chengdu', 'Mianyang', 'Deyang', 'Yibin'],
      'Hubei': ['Wuhan', 'Yichang', 'Xiangyang', 'Jingzhou'],
      'Jiangsu': ['Nanjing', 'Suzhou', 'Wuxi', 'Nantong'],
      'Shandong': ['Jinan', 'Qingdao', 'Yantai', 'Weifang'],
    },
    'France': {
      'Ile-de-France': [
        'Paris',
        'Boulogne-Billancourt',
        'Saint-Denis',
        'Versailles'
      ],
      "Provence-Alpes-Cote d'Azur": [
        'Marseille',
        'Nice',
        'Toulon',
        'Aix-en-Provence'
      ],
      'Auvergne-Rhone-Alpes': [
        'Lyon',
        'Grenoble',
        'Saint-Etienne',
        'Clermont-Ferrand'
      ],
      'Occitanie': ['Toulouse', 'Montpellier', 'Nimes', 'Perpignan'],
      'Nouvelle-Aquitaine': ['Bordeaux', 'Limoges', 'Poitiers', 'La Rochelle'],
      'Hauts-de-France': ['Lille', 'Amiens', 'Roubaix', 'Dunkerque'],
    },
    'Germany': {
      'Bavaria': ['Munich', 'Nuremberg', 'Augsburg', 'Regensburg'],
      'North Rhine-Westphalia': ['Cologne', 'Dusseldorf', 'Dortmund', 'Essen'],
      'Baden-Wurttemberg': [
        'Stuttgart',
        'Mannheim',
        'Karlsruhe',
        'Freiburg im Breisgau'
      ],
      'Hesse': ['Frankfurt', 'Wiesbaden', 'Darmstadt', 'Kassel'],
      'Lower Saxony': ['Hanover', 'Braunschweig', 'Osnabruck', 'Oldenburg'],
      'Berlin': ['Berlin', 'Spandau', 'Pankow', 'Neukolln'],
    },
    'Indonesia': {
      'Jakarta Special Capital Region': [
        'Jakarta',
        'South Jakarta',
        'West Jakarta',
        'East Jakarta'
      ],
      'West Java': ['Bandung', 'Bekasi', 'Bogor', 'Depok'],
      'East Java': ['Surabaya', 'Malang', 'Sidoarjo', 'Kediri'],
      'Central Java': ['Semarang', 'Surakarta', 'Magelang', 'Pekalongan'],
      'Bali': ['Denpasar', 'Singaraja', 'Ubud', 'Kuta'],
      'South Sulawesi': ['Makassar', 'Parepare', 'Palopo', 'Watampone'],
      'North Sumatra': ['Medan', 'Binjai', 'Pematangsiantar', 'Tebing Tinggi'],
    },
    'Ireland': {
      'Leinster': ['Dublin', 'Drogheda', 'Bray', 'Kilkenny'],
      'Munster': ['Cork', 'Limerick', 'Waterford', 'Tralee'],
      'Connacht': ['Galway', 'Sligo', 'Castlebar', 'Ballina'],
      'Ulster': ['Letterkenny', 'Cavan', 'Monaghan', 'Buncrana'],
    },
    'Italy': {
      'Lazio': ['Rome', 'Latina', 'Frosinone', 'Viterbo'],
      'Lombardy': ['Milan', 'Brescia', 'Bergamo', 'Monza'],
      'Campania': ['Naples', 'Salerno', 'Caserta', 'Avellino'],
      'Sicily': ['Palermo', 'Catania', 'Messina', 'Syracuse'],
      'Veneto': ['Venice', 'Verona', 'Padua', 'Vicenza'],
      'Emilia-Romagna': ['Bologna', 'Parma', 'Modena', 'Ravenna'],
      'Tuscany': ['Florence', 'Prato', 'Pisa', 'Livorno'],
    },
    'Japan': {
      'Tokyo': ['Shinjuku', 'Shibuya', 'Setagaya', 'Hachioji'],
      'Osaka Prefecture': ['Osaka', 'Sakai', 'Higashiosaka', 'Toyonaka'],
      'Kanagawa Prefecture': ['Yokohama', 'Kawasaki', 'Sagamihara', 'Yokosuka'],
      'Aichi Prefecture': ['Nagoya', 'Toyota', 'Okazaki', 'Ichinomiya'],
      'Hokkaido': ['Sapporo', 'Hakodate', 'Asahikawa', 'Kushiro'],
      'Fukuoka Prefecture': ['Fukuoka', 'Kitakyushu', 'Kurume', 'Omuta'],
      'Kyoto Prefecture': ['Kyoto', 'Uji', 'Kameoka', 'Maizuru'],
    },
    'Malaysia': {
      'Selangor': ['Shah Alam', 'Petaling Jaya', 'Subang Jaya', 'Klang'],
      'Johor': ['Johor Bahru', 'Batu Pahat', 'Muar', 'Kluang'],
      'Penang': [
        'George Town',
        'Butterworth',
        'Bukit Mertajam',
        'Nibong Tebal'
      ],
      'Sabah': ['Kota Kinabalu', 'Sandakan', 'Tawau', 'Lahad Datu'],
      'Sarawak': ['Kuching', 'Miri', 'Sibu', 'Bintulu'],
      'Kuala Lumpur': ['Kuala Lumpur', 'Setapak', 'Cheras', 'Kepong'],
      'Perak': ['Ipoh', 'Taiping', 'Teluk Intan', 'Sitiawan'],
    },
    'Maldives': {
      'Kaafu Atoll': ['Male', 'Hulhumale', 'Maafushi'],
      'Addu Atoll': ['Hithadhoo', 'Maradhoo', 'Feydhoo'],
      'Haa Dhaalu Atoll': ['Kulhudhuffushi', 'Nolhivaram', 'Hanimaadhoo'],
    },
    'Myanmar': {
      'Yangon Region': ['Yangon', 'Thanlyin', 'Insein', 'Hmawbi'],
      'Mandalay Region': ['Mandalay', 'Pyin Oo Lwin', 'Meiktila', 'Myingyan'],
      'Naypyidaw Union Territory': ['Naypyidaw', 'Pyinmana', 'Lewe'],
      'Shan State': ['Taunggyi', 'Lashio', 'Kengtung', 'Kalaw'],
      'Mon State': ['Mawlamyine', 'Thaton', 'Kyaikto', 'Ye'],
    },
    'Nepal': {
      'Bagmati Province': ['Kathmandu', 'Lalitpur', 'Bhaktapur', 'Hetauda'],
      'Koshi Province': ['Biratnagar', 'Dharan', 'Itahari', 'Birtamod'],
      'Gandaki Province': ['Pokhara', 'Baglung', 'Gorkha', 'Damauli'],
      'Lumbini Province': [
        'Butwal',
        'Siddharthanagar',
        'Nepalgunj',
        'Tulsipur'
      ],
      'Madhesh Province': ['Janakpur', 'Birgunj', 'Kalaiya', 'Rajbiraj'],
      'Karnali Province': ['Birendranagar', 'Jumla', 'Dailekh', 'Salyan'],
    },
    'Netherlands': {
      'North Holland': ['Amsterdam', 'Haarlem', 'Alkmaar', 'Hilversum'],
      'South Holland': ['Rotterdam', 'The Hague', 'Leiden', 'Dordrecht'],
      'Utrecht': ['Utrecht', 'Amersfoort', 'Veenendaal', 'Nieuwegein'],
      'North Brabant': ['Eindhoven', 'Tilburg', "'s-Hertogenbosch", 'Breda'],
      'Gelderland': ['Arnhem', 'Nijmegen', 'Apeldoorn', 'Ede'],
    },
    'New Zealand': {
      'Auckland Region': ['Auckland', 'Manukau', 'North Shore', 'Papakura'],
      'Wellington Region': [
        'Wellington',
        'Lower Hutt',
        'Porirua',
        'Upper Hutt'
      ],
      'Canterbury Region': ['Christchurch', 'Timaru', 'Ashburton', 'Rangiora'],
      'Waikato Region': ['Hamilton', 'Tauranga', 'Cambridge', 'Te Awamutu'],
      'Otago Region': ['Dunedin', 'Queenstown', 'Oamaru', 'Balclutha'],
    },
    'Oman': {
      'Muscat Governorate': ['Muscat', 'Seeb', 'Muttrah', 'Bawshar'],
      'Dhofar Governorate': ['Salalah', 'Taqah', 'Mirbat', 'Thumrait'],
      'Al Batinah North Governorate': ['Sohar', 'Shinas', 'Liwa', 'Saham'],
      'Al Dakhiliyah Governorate': ['Nizwa', 'Bahla', 'Adam', 'Samail'],
    },
    'Pakistan': {
      'Punjab': ['Lahore', 'Rawalpindi', 'Faisalabad', 'Multan'],
      'Sindh': ['Karachi', 'Hyderabad', 'Sukkur', 'Larkana'],
      'Khyber Pakhtunkhwa': ['Peshawar', 'Mardan', 'Abbottabad', 'Swat'],
      'Balochistan': ['Quetta', 'Gwadar', 'Khuzdar', 'Turbat'],
      'Islamabad Capital Territory': ['Islamabad', 'Bhara Kahu', 'Rawat'],
      'Gilgit-Baltistan': ['Gilgit', 'Skardu', 'Hunza', 'Khaplu'],
    },
    'Qatar': {
      'Doha Municipality': ['Doha', 'Al Wakrah', 'Al Khor'],
      'Al Rayyan Municipality': ['Al Rayyan', 'Lusail', 'Umm Salal'],
      'Al Daayen Municipality': ['Al Daayen', 'Simaisma', 'Umm Qarn'],
    },
    'Saudi Arabia': {
      'Riyadh Province': ['Riyadh', 'Al Kharj', 'Al Majmaah', 'Ad Diriyah'],
      'Makkah Province': ['Jeddah', 'Mecca', 'Taif', 'Rabigh'],
      'Eastern Province': ['Dammam', 'Khobar', 'Dhahran', 'Jubail'],
      'Medina Province': ['Medina', 'Yanbu', 'Al Ula', 'Badr'],
      'Asir Province': ['Abha', 'Khamis Mushait', 'Bisha', 'Muhayil'],
    },
    'Singapore': {
      'Central Region': ['Singapore', 'Bukit Merah', 'Toa Payoh', 'Kallang'],
      'East Region': ['Tampines', 'Pasir Ris', 'Bedok', 'Changi'],
      'North Region': ['Woodlands', 'Yishun', 'Sembawang', 'Sungei Kadut'],
      'North-East Region': ['Hougang', 'Sengkang', 'Punggol', 'Serangoon'],
      'West Region': ['Jurong East', 'Jurong West', 'Bukit Batok', 'Clementi'],
    },
    'South Africa': {
      'Gauteng': ['Johannesburg', 'Pretoria', 'Soweto', 'Midrand'],
      'Western Cape': ['Cape Town', 'Stellenbosch', 'Paarl', 'George'],
      'KwaZulu-Natal': [
        'Durban',
        'Pietermaritzburg',
        'Richards Bay',
        'Newcastle'
      ],
      'Eastern Cape': ['Gqeberha', 'East London', 'Mthatha', 'Bhisho'],
      'Free State': ['Bloemfontein', 'Welkom', 'Bethlehem', 'Sasolburg'],
    },
    'Sri Lanka': {
      'Western Province': [
        'Colombo',
        'Sri Jayawardenepura Kotte',
        'Negombo',
        'Moratuwa'
      ],
      'Central Province': ['Kandy', 'Nuwara Eliya', 'Matale', 'Gampola'],
      'Southern Province': ['Galle', 'Matara', 'Hambantota', 'Tangalle'],
      'Northern Province': ['Jaffna', 'Kilinochchi', 'Mannar', 'Vavuniya'],
      'North Western Province': [
        'Kurunegala',
        'Puttalam',
        'Chilaw',
        'Kuliyapitiya'
      ],
    },
    'Switzerland': {
      'Canton of Zurich': ['Zurich', 'Winterthur', 'Uster', 'Dietikon'],
      'Canton of Geneva': ['Geneva', 'Carouge', 'Lancy', 'Vernier'],
      'Canton of Vaud': ['Lausanne', 'Yverdon-les-Bains', 'Montreux', 'Nyon'],
      'Canton of Bern': ['Bern', 'Biel/Bienne', 'Thun', 'Koniz'],
      'Canton of Basel-Stadt': ['Basel', 'Riehen', 'Bettingen'],
    },
    'Thailand': {
      'Bangkok': ['Bangkok', 'Thon Buri', 'Bang Kapi', 'Min Buri'],
      'Chiang Mai Province': [
        'Chiang Mai',
        'Fang',
        'San Kamphaeng',
        'Chom Thong'
      ],
      'Chon Buri Province': [
        'Pattaya',
        'Si Racha',
        'Chon Buri',
        'Laem Chabang'
      ],
      'Phuket Province': ['Phuket', 'Patong', 'Karon', 'Rawai'],
      'Nakhon Ratchasima Province': [
        'Nakhon Ratchasima',
        'Pak Chong',
        'Sikhio',
        'Non Sung'
      ],
      'Khon Kaen Province': ['Khon Kaen', 'Chum Phae', 'Phon', 'Nam Phong'],
    },
    'United Arab Emirates': {
      'Abu Dhabi': ['Abu Dhabi', 'Al Ain', 'Madinat Zayed', 'Ruwais'],
      'Dubai': ['Dubai', 'Jebel Ali', 'Hatta', 'Al Awir'],
      'Sharjah': ['Sharjah', 'Khor Fakkan', 'Kalba', 'Dibba Al-Hisn'],
      'Ajman': ['Ajman', 'Masfout', 'Al Manama'],
      'Ras Al Khaimah': ['Ras Al Khaimah', 'Al Jazirah Al Hamra', 'Digdaga'],
      'Fujairah': ['Fujairah', 'Dibba Al Fujairah', 'Masafi'],
      'Umm Al Quwain': ['Umm Al Quwain', 'Falaj Al Mualla', 'Al Salamah'],
    },
    'United Kingdom': {
      'England': ['London', 'Birmingham', 'Manchester', 'Leeds', 'Liverpool'],
      'Scotland': ['Glasgow', 'Edinburgh', 'Aberdeen', 'Dundee'],
      'Wales': ['Cardiff', 'Swansea', 'Newport', 'Wrexham'],
      'Northern Ireland': ['Belfast', 'Derry', 'Lisburn', 'Newry'],
    },
    'United States': {
      'California': ['Los Angeles', 'San Diego', 'San Jose', 'San Francisco'],
      'Texas': ['Houston', 'Dallas', 'Austin', 'San Antonio'],
      'New York': ['New York City', 'Buffalo', 'Rochester', 'Albany'],
      'Florida': ['Jacksonville', 'Miami', 'Tampa', 'Orlando'],
      'Illinois': ['Chicago', 'Aurora', 'Naperville', 'Rockford'],
      'Pennsylvania': ['Philadelphia', 'Pittsburgh', 'Allentown', 'Erie'],
      'Washington': ['Seattle', 'Spokane', 'Tacoma', 'Vancouver'],
      'Massachusetts': ['Boston', 'Worcester', 'Springfield', 'Cambridge'],
      'Georgia': ['Atlanta', 'Augusta', 'Columbus', 'Savannah'],
    },
  };
}
