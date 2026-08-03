const SECTION_KEYS = [
  'hero','stay_overview','quick_access','wifi','room_gallery','room_guide',
  'hotel_facilities','dining','guest_services','safety','important_contacts',
  'stay_connected','local_convenience','payment','feedback','google_review',
  'policies','thank_you',
]

const EN_SECTIONS = {
  hero: ['01 — Welcome','Welcome','Your secure digital companion for a comfortable stay.'],
  stay_overview: ['02 — Stay Overview','Your Stay at a Glance','Room, timings and essential information.'],
  quick_access: ['03 — Concierge','Quick Access','Tap any card for instant assistance.'],
  wifi: ['04 — Connectivity','Wi-Fi Access','Copy the details and connect instantly.'],
  room_gallery: ['05 — Your Room','Room Experience','A visual introduction to your room.'],
  room_guide: ['06 — How to Use','Room Guide','Open a card to view complete instructions.'],
  hotel_facilities: ['07 — Facilities','Hotel Facilities','Explore facilities available at the property.'],
  dining: ['08 — Dining','Dining & Room Service','Browse the menu and order from your room.'],
  guest_services: ['09 — Guest Services','Need Something?','Request essentials directly from your room.'],
  safety: ['10 — Safety','Your Safety, Our Priority','Important information for a safe and comfortable stay.'],
  important_contacts: ['11 — Contacts','We’re Always Here','Reach the right support in one tap.'],
  stay_connected: ['12 — Stay Connected','Stay Connected','Connect with the hotel online.'],
  local_convenience: ['13 — Local Convenience','Discover the Local Area','Nearby essentials and local experiences.'],
  payment: ['14 — Payment','Easy Payment','Pay using the hotel’s verified UPI details.'],
  feedback: ['15 — Private Feedback','How Was Your Stay?','Share private feedback directly with the hotel.'],
  google_review: ['16 — Review & Rewards','Share Your Experience','Your honest review helps future guests.'],
  policies: ['17 — Policies','Hotel Policies','Review important terms for your stay.'],
  thank_you: ['18 — Until Next Time','Thank You for Choosing Us','We hope your stay feels comfortable, safe and memorable.'],
}

const HI_SECTIONS = {
  hero: ['01 — स्वागत','स्वागत है','आपके आरामदायक प्रवास के लिए सुरक्षित डिजिटल साथी।'],
  stay_overview: ['02 — प्रवास विवरण','आपके प्रवास की जानकारी','कमरा, समय और आवश्यक जानकारी।'],
  quick_access: ['03 — कंसीयर्ज','त्वरित सहायता','तुरंत सहायता के लिए किसी कार्ड पर टैप करें।'],
  wifi: ['04 — कनेक्टिविटी','वाई-फाई एक्सेस','विवरण कॉपी करें और तुरंत कनेक्ट हों।'],
  room_gallery: ['05 — आपका कमरा','रूम अनुभव','अपने कमरे की तस्वीरें देखें।'],
  room_guide: ['06 — उपयोग कैसे करें','रूम गाइड','पूरे निर्देश देखने के लिए कार्ड खोलें।'],
  hotel_facilities: ['07 — सुविधाएँ','होटल सुविधाएँ','होटल में उपलब्ध सुविधाएँ देखें।'],
  dining: ['08 — भोजन','डाइनिंग और रूम सर्विस','मेन्यू देखें और कमरे से ऑर्डर करें।'],
  guest_services: ['09 — अतिथि सेवाएँ','कुछ चाहिए?','अपने कमरे से आवश्यक सेवा का अनुरोध करें।'],
  safety: ['10 — सुरक्षा','आपकी सुरक्षा हमारी प्राथमिकता','सुरक्षित और आरामदायक प्रवास के लिए जरूरी जानकारी।'],
  important_contacts: ['11 — संपर्क','हम हमेशा उपलब्ध हैं','सही सहायता तक एक टैप में पहुँचें।'],
  stay_connected: ['12 — जुड़े रहें','होटल से जुड़े रहें','होटल से ऑनलाइन संपर्क करें।'],
  local_convenience: ['13 — स्थानीय सुविधा','आस-पास की जगहें','पास की जरूरी सेवाएँ और अनुभव खोजें।'],
  payment: ['14 — भुगतान','आसान भुगतान','होटल के सत्यापित UPI विवरण से भुगतान करें।'],
  feedback: ['15 — निजी फीडबैक','आपका अनुभव कैसा रहा?','अपना निजी फीडबैक सीधे होटल को भेजें।'],
  google_review: ['16 — रिव्यू और रिवॉर्ड','अपना अनुभव साझा करें','आपका ईमानदार रिव्यू अन्य अतिथियों की मदद करता है।'],
  policies: ['17 — नीतियाँ','होटल नीतियाँ','अपने प्रवास की महत्वपूर्ण शर्तें देखें।'],
  thank_you: ['18 — फिर मिलेंगे','हमें चुनने के लिए धन्यवाद','हम आशा करते हैं कि आपका प्रवास आरामदायक और यादगार रहा।'],
}

const MR_SECTIONS = {
  hero: ['01 — स्वागत','स्वागत आहे','आपल्या आरामदायक मुक्कामासाठी सुरक्षित डिजिटल साथी.'],
  stay_overview: ['02 — मुक्काम माहिती','आपल्या मुक्कामाची माहिती','खोली, वेळा आणि आवश्यक माहिती.'],
  quick_access: ['03 — कंसीयर्ज','त्वरित मदत','त्वरित मदतीसाठी कार्डवर टॅप करा.'],
  wifi: ['04 — कनेक्टिव्हिटी','वाय-फाय प्रवेश','तपशील कॉपी करा आणि लगेच कनेक्ट व्हा.'],
  room_gallery: ['05 — आपली खोली','रूम अनुभव','आपल्या खोलीची छायाचित्रे पहा.'],
  room_guide: ['06 — वापर कसा करावा','रूम गाइड','पूर्ण सूचना पाहण्यासाठी कार्ड उघडा.'],
  hotel_facilities: ['07 — सुविधा','हॉटेल सुविधा','हॉटेलमधील उपलब्ध सुविधा पहा.'],
  dining: ['08 — भोजन','डायनिंग आणि रूम सर्विस','मेन्यू पहा आणि खोलीतून ऑर्डर करा.'],
  guest_services: ['09 — अतिथी सेवा','काही हवे आहे?','खोलीतून आवश्यक सेवा मागवा.'],
  safety: ['10 — सुरक्षितता','आपली सुरक्षितता आमची प्राथमिकता','सुरक्षित आणि आरामदायक मुक्कामासाठी माहिती.'],
  important_contacts: ['11 — संपर्क','आम्ही नेहमी उपलब्ध आहोत','योग्य मदत एका टॅपमध्ये मिळवा.'],
  stay_connected: ['12 — संपर्कात रहा','हॉटेलशी जोडलेले रहा','हॉटेलशी ऑनलाइन संपर्क करा.'],
  local_convenience: ['13 — स्थानिक सुविधा','आजूबाजूचा परिसर शोधा','जवळच्या आवश्यक सेवा आणि अनुभव शोधा.'],
  payment: ['14 — पेमेंट','सोपे पेमेंट','हॉटेलच्या सत्यापित UPI तपशीलाने पेमेंट करा.'],
  feedback: ['15 — खाजगी फीडबॅक','आपला अनुभव कसा होता?','आपला खाजगी फीडबॅक थेट हॉटेलला पाठवा.'],
  google_review: ['16 — रिव्यू आणि रिवॉर्ड','आपला अनुभव शेअर करा','आपला प्रामाणिक रिव्यू इतर अतिथींना मदत करतो.'],
  policies: ['17 — धोरणे','हॉटेल धोरणे','आपल्या मुक्कामाच्या महत्त्वाच्या अटी पहा.'],
  thank_you: ['18 — पुन्हा भेटू','आमची निवड केल्याबद्दल धन्यवाद','आपला मुक्काम आरामदायक आणि संस्मरणीय झाला अशी आशा आहे.'],
}

const TA_SECTIONS = {
  hero: ['01 — வரவேற்பு','வரவேற்கிறோம்','உங்கள் வசதியான தங்குதலுக்கான பாதுகாப்பான டிஜிட்டல் வழிகாட்டி.'],
  stay_overview: ['02 — தங்கும் விவரம்','உங்கள் தங்கும் தகவல்','அறை, நேரம் மற்றும் முக்கிய தகவல்கள்.'],
  quick_access: ['03 — உதவி','விரைவு அணுகல்','உடனடி உதவிக்காக ஒரு அட்டையைத் தட்டவும்.'],
  wifi: ['04 — இணைப்பு','வை-ஃபை அணுகல்','விவரங்களை நகலெடுத்து உடனே இணைக்கவும்.'],
  room_gallery: ['05 — உங்கள் அறை','அறை அனுபவம்','உங்கள் அறையின் படங்களைப் பாருங்கள்.'],
  room_guide: ['06 — பயன்படுத்துவது எப்படி','அறை வழிகாட்டி','முழு வழிமுறைகளைக் காண அட்டையைத் திறக்கவும்.'],
  hotel_facilities: ['07 — வசதிகள்','ஹோட்டல் வசதிகள்','ஹோட்டலில் உள்ள வசதிகளைப் பாருங்கள்.'],
  dining: ['08 — உணவு','உணவு மற்றும் ரூம் சர்வீஸ்','மெனுவைப் பார்த்து அறையிலிருந்து ஆர்டர் செய்யவும்.'],
  guest_services: ['09 — விருந்தினர் சேவைகள்','ஏதாவது வேண்டுமா?','அறையிலிருந்து தேவையான சேவையை கோரவும்.'],
  safety: ['10 — பாதுகாப்பு','உங்கள் பாதுகாப்பே எங்கள் முன்னுரிமை','பாதுகாப்பான தங்குதலுக்கான முக்கிய தகவல்.'],
  important_contacts: ['11 — தொடர்புகள்','நாங்கள் எப்போதும் இருக்கிறோம்','ஒரே தட்டலில் சரியான உதவியைப் பெறுங்கள்.'],
  stay_connected: ['12 — தொடர்பில் இருங்கள்','ஹோட்டலுடன் இணைந்திருங்கள்','ஹோட்டலை ஆன்லைனில் தொடர்புகொள்ளுங்கள்.'],
  local_convenience: ['13 — உள்ளூர் வசதி','அருகிலுள்ள இடங்களை கண்டறியுங்கள்','அருகிலுள்ள அத்தியாவசிய சேவைகள் மற்றும் அனுபவங்கள்.'],
  payment: ['14 — கட்டணம்','எளிய கட்டணம்','சரிபார்க்கப்பட்ட UPI விவரங்களைப் பயன்படுத்தி செலுத்தவும்.'],
  feedback: ['15 — தனிப்பட்ட கருத்து','உங்கள் அனுபவம் எப்படி?','தனிப்பட்ட கருத்தை ஹோட்டலுக்கு அனுப்பவும்.'],
  google_review: ['16 — மதிப்புரை மற்றும் பரிசு','உங்கள் அனுபவத்தை பகிருங்கள்','உங்கள் மதிப்புரை மற்ற விருந்தினர்களுக்கு உதவும்.'],
  policies: ['17 — கொள்கைகள்','ஹோட்டல் கொள்கைகள்','உங்கள் தங்குதலுக்கான முக்கிய விதிகளைப் பாருங்கள்.'],
  thank_you: ['18 — மீண்டும் சந்திப்போம்','எங்களைத் தேர்ந்தெடுத்ததற்கு நன்றி','உங்கள் தங்குதல் வசதியாகவும் நினைவாகவும் இருந்ததாக நம்புகிறோம்.'],
}

const SECTION_PACKS = { en: EN_SECTIONS, hi: HI_SECTIONS, mr: MR_SECTIONS, ta: TA_SECTIONS }

const ITEM_PACKS = {
  en: {
    housekeeping: ['Housekeeping','Request room cleaning support.','Request now'],
    drinking_water: ['Drinking Water','Request drinking water for your room.','Request now'],
    fresh_towels: ['Fresh Towels','Request additional fresh towels.','Request now'],
    food_menu: ['Food Menu','Browse the hotel menu and order food.','View menu'],
    checkout_request: ['Checkout','Notify reception that you are preparing to check out.','Notify reception'],
    reception_contact: ['Reception / Room Service','Call the hotel front desk for assistance.','Call now'],
    whatsapp_contact: ['WhatsApp Reception','Message the hotel for support.','Open WhatsApp'],
    hotel_email: ['Email Hotel','Send an email to the hotel team.','Send email'],
    instagram: ['Instagram','Follow the hotel on Instagram.','Follow'],
    hotel_website: ['Hotel Website','Visit the official hotel website.','Open website'],
    hotel_location: ['Hotel Location','Open the hotel location in Google Maps.','Open Maps'],
    nearby_restaurants: ['Nearby Restaurants','Discover nearby dining options.','Explore'],
    medical_support: ['Nearby Medical Support','Find a nearby hospital, clinic or pharmacy.','Explore'],
    nearby_atms: ['Nearby ATMs','Find nearby ATM services.','Explore'],
    shopping_essentials: ['Shopping & Essentials','Find nearby stores and essentials.','Explore'],
    tourist_places: ['Tourist Places','Explore nearby attractions.','Explore'],
    transport_assistance: ['Transport Assistance','Contact the hotel for transport help.','Contact'],
    air_conditioner: ['Air Conditioner','Use the AC and remote safely.','View instructions'],
    television_remote: ['Television & Remote','Use the TV, set-top box and remote.','View instructions'],
    hot_water_geyser: ['Hot Water & Geyser','Use hot water or the geyser safely.','View instructions'],
    bathtub_controls: ['Bathtub','Use the bathtub controls safely.','View instructions'],
    safe_locker: ['Safe Locker','Use and reset the safe locker.','View instructions'],
  },
  hi: {
    housekeeping: ['हाउसकीपिंग','कमरे की सफाई का अनुरोध करें।','अभी अनुरोध करें'],
    drinking_water: ['पीने का पानी','कमरे के लिए पीने का पानी मंगाएँ।','अभी अनुरोध करें'],
    fresh_towels: ['ताज़े तौलिए','अतिरिक्त साफ तौलिए मंगाएँ।','अभी अनुरोध करें'],
    food_menu: ['फूड मेन्यू','होटल मेन्यू देखें और खाना ऑर्डर करें।','मेन्यू देखें'],
    checkout_request: ['चेकआउट','रिसेप्शन को बताएं कि आप चेकआउट की तैयारी कर रहे हैं।','रिसेप्शन को बताएं'],
    reception_contact: ['रिसेप्शन / रूम सर्विस','सहायता के लिए फ्रंट डेस्क को कॉल करें।','अभी कॉल करें'],
    whatsapp_contact: ['व्हाट्सऐप रिसेप्शन','सहायता के लिए होटल को संदेश भेजें।','व्हाट्सऐप खोलें'],
    hotel_email: ['होटल ईमेल','होटल टीम को ईमेल भेजें।','ईमेल भेजें'],
    instagram: ['इंस्टाग्राम','होटल को इंस्टाग्राम पर फॉलो करें।','फॉलो करें'],
    hotel_website: ['होटल वेबसाइट','होटल की आधिकारिक वेबसाइट देखें।','वेबसाइट खोलें'],
    hotel_location: ['होटल लोकेशन','Google Maps में होटल खोलें।','मैप खोलें'],
    nearby_restaurants: ['नज़दीकी रेस्टोरेंट','पास के भोजन विकल्प खोजें।','देखें'],
    medical_support: ['नज़दीकी मेडिकल सहायता','पास का अस्पताल, क्लिनिक या मेडिकल खोजें।','देखें'],
    nearby_atms: ['नज़दीकी ATM','पास का ATM खोजें।','देखें'],
    shopping_essentials: ['शॉपिंग और ज़रूरी सामान','पास की दुकानें खोजें।','देखें'],
    tourist_places: ['पर्यटन स्थल','पास के आकर्षण खोजें।','देखें'],
    transport_assistance: ['यातायात सहायता','यातायात के लिए होटल से संपर्क करें।','संपर्क करें'],
    air_conditioner: ['एयर कंडीशनर','AC और रिमोट का सुरक्षित उपयोग करें।','निर्देश देखें'],
    television_remote: ['टेलीविज़न और रिमोट','टीवी, सेट-टॉप बॉक्स और रिमोट का उपयोग करें।','निर्देश देखें'],
    hot_water_geyser: ['गर्म पानी और गीजर','गर्म पानी या गीजर का सुरक्षित उपयोग करें।','निर्देश देखें'],
    bathtub_controls: ['बाथटब','बाथटब नियंत्रण का सुरक्षित उपयोग करें।','निर्देश देखें'],
    safe_locker: ['सेफ लॉकर','सेफ लॉकर का उपयोग और रीसेट करें।','निर्देश देखें'],
  },
  mr: {
    housekeeping: ['हाउसकीपिंग','खोली स्वच्छतेची विनंती करा.','आता विनंती करा'],
    drinking_water: ['पिण्याचे पाणी','खोलीसाठी पिण्याचे पाणी मागवा.','आता विनंती करा'],
    fresh_towels: ['स्वच्छ टॉवेल','अतिरिक्त स्वच्छ टॉवेल मागवा.','आता विनंती करा'],
    food_menu: ['फूड मेन्यू','हॉटेल मेन्यू पहा आणि जेवण ऑर्डर करा.','मेन्यू पहा'],
    checkout_request: ['चेकआउट','आपण चेकआउटची तयारी करत आहात हे रिसेप्शनला कळवा.','रिसेप्शनला कळवा'],
    reception_contact: ['रिसेप्शन / रूम सर्विस','मदतीसाठी फ्रंट डेस्कला कॉल करा.','आता कॉल करा'],
    whatsapp_contact: ['व्हॉट्सअॅप रिसेप्शन','मदतीसाठी हॉटेलला संदेश पाठवा.','व्हॉट्सअॅप उघडा'],
    hotel_email: ['हॉटेल ईमेल','हॉटेल टीमला ईमेल पाठवा.','ईमेल पाठवा'],
    instagram: ['इंस्टाग्राम','हॉटेलला इंस्टाग्रामवर फॉलो करा.','फॉलो करा'],
    hotel_website: ['हॉटेल वेबसाइट','हॉटेलची अधिकृत वेबसाइट पहा.','वेबसाइट उघडा'],
    hotel_location: ['हॉटेल लोकेशन','Google Maps मध्ये हॉटेल उघडा.','नकाशा उघडा'],
    nearby_restaurants: ['जवळची रेस्टॉरंट्स','जवळचे भोजन पर्याय शोधा.','पहा'],
    medical_support: ['जवळची वैद्यकीय मदत','जवळचे रुग्णालय, क्लिनिक किंवा मेडिकल शोधा.','पहा'],
    nearby_atms: ['जवळचे ATM','जवळचे ATM शोधा.','पहा'],
    shopping_essentials: ['खरेदी आणि आवश्यक वस्तू','जवळची दुकाने शोधा.','पहा'],
    tourist_places: ['पर्यटन स्थळे','जवळची आकर्षणे शोधा.','पहा'],
    transport_assistance: ['वाहतूक मदत','वाहतुकीसाठी हॉटेलशी संपर्क करा.','संपर्क करा'],
    air_conditioner: ['एअर कंडिशनर','AC आणि रिमोट सुरक्षितपणे वापरा.','सूचना पहा'],
    television_remote: ['टेलिव्हिजन आणि रिमोट','टीव्ही, सेट-टॉप बॉक्स आणि रिमोट वापरा.','सूचना पहा'],
    hot_water_geyser: ['गरम पाणी आणि गीझर','गरम पाणी किंवा गीझर सुरक्षितपणे वापरा.','सूचना पहा'],
    bathtub_controls: ['बाथटब','बाथटब नियंत्रण सुरक्षितपणे वापरा.','सूचना पहा'],
    safe_locker: ['सेफ लॉकर','सेफ लॉकर वापरा आणि रीसेट करा.','सूचना पहा'],
  },
  ta: {
    housekeeping: ['ஹவுஸ்கீப்பிங்','அறை சுத்தம் செய்ய கோரிக்கை விடுக்கவும்.','இப்போது கோரவும்'],
    drinking_water: ['குடிநீர்','அறைக்கு குடிநீர் கோரவும்.','இப்போது கோரவும்'],
    fresh_towels: ['புதிய துண்டுகள்','கூடுதல் சுத்தமான துண்டுகள் கோரவும்.','இப்போது கோரவும்'],
    food_menu: ['உணவு மெனு','ஹோட்டல் மெனுவைப் பார்த்து உணவு ஆர்டர் செய்யவும்.','மெனு பார்க்க'],
    checkout_request: ['செக்-அவுட்','நீங்கள் செக்-அவுட் செய்ய தயாராக இருப்பதை ரிசப்ஷனுக்கு தெரிவிக்கவும்.','தெரிவிக்கவும்'],
    reception_contact: ['ரிசப்ஷன் / ரூம் சர்வீஸ்','உதவிக்கு முன் மேசையை அழைக்கவும்.','இப்போது அழைக்கவும்'],
    whatsapp_contact: ['வாட்ஸ்அப் ரிசப்ஷன்','உதவிக்காக ஹோட்டலுக்கு செய்தி அனுப்பவும்.','வாட்ஸ்அப் திறக்க'],
    hotel_email: ['ஹோட்டல் மின்னஞ்சல்','ஹோட்டல் குழுவுக்கு மின்னஞ்சல் அனுப்பவும்.','மின்னஞ்சல் அனுப்ப'],
    instagram: ['இன்ஸ்டாகிராம்','ஹோட்டலை இன்ஸ்டாகிராமில் பின்தொடரவும்.','பின்தொடரவும்'],
    hotel_website: ['ஹோட்டல் இணையதளம்','அதிகாரப்பூர்வ இணையதளத்தைப் பாருங்கள்.','இணையதளம் திறக்க'],
    hotel_location: ['ஹோட்டல் இருப்பிடம்','Google Maps-ல் ஹோட்டலைத் திறக்கவும்.','மாப்பை திறக்க'],
    nearby_restaurants: ['அருகிலுள்ள உணவகங்கள்','அருகிலுள்ள உணவு விருப்பங்களை கண்டறியவும்.','பார்க்க'],
    medical_support: ['அருகிலுள்ள மருத்துவ உதவி','அருகிலுள்ள மருத்துவமனை அல்லது மருந்தகத்தை கண்டறியவும்.','பார்க்க'],
    nearby_atms: ['அருகிலுள்ள ATM','அருகிலுள்ள ATM சேவைகளை கண்டறியவும்.','பார்க்க'],
    shopping_essentials: ['ஷாப்பிங் மற்றும் அத்தியாவசியங்கள்','அருகிலுள்ள கடைகளை கண்டறியவும்.','பார்க்க'],
    tourist_places: ['சுற்றுலா இடங்கள்','அருகிலுள்ள சுற்றுலா இடங்களை கண்டறியவும்.','பார்க்க'],
    transport_assistance: ['போக்குவரத்து உதவி','போக்குவரத்துக்கு ஹோட்டலை தொடர்புகொள்ளவும்.','தொடர்புகொள்ள'],
    air_conditioner: ['ஏர் கண்டிஷனர்','AC மற்றும் ரிமோட்டை பாதுகாப்பாக பயன்படுத்தவும்.','வழிமுறை பார்க்க'],
    television_remote: ['டிவி மற்றும் ரிமோட்','டிவி, செட்-டாப் பாக்ஸ் மற்றும் ரிமோட்டை பயன்படுத்தவும்.','வழிமுறை பார்க்க'],
    hot_water_geyser: ['சூடுநீர் மற்றும் கீசர்','சூடுநீர் அல்லது கீசரை பாதுகாப்பாக பயன்படுத்தவும்.','வழிமுறை பார்க்க'],
    bathtub_controls: ['பாத் டப்','பாத் டப் கட்டுப்பாடுகளை பாதுகாப்பாக பயன்படுத்தவும்.','வழிமுறை பார்க்க'],
    safe_locker: ['பாதுகாப்புப் பெட்டி','பாதுகாப்புப் பெட்டியை பயன்படுத்தி மீட்டமைக்கவும்.','வழிமுறை பார்க்க'],
  },
}

const INSTRUCTION_PACKS = {
  en: {
    air_conditioner: ['Press the power button on the AC remote.','Select Cool mode.','Set the temperature between 22°C and 24°C.','Use Swing to adjust airflow.','Contact reception if the AC does not respond.'],
    television_remote: ['Switch on the TV and set-top box.','Select the correct HDMI/input source.','Use the channel or app controls on the remote.','Keep the remotes in the room after use.','Contact reception if there is no signal.'],
    hot_water_geyser: ['Switch on the geyser only when required.','Wait for the water to heat before use.','Test the water temperature carefully.','Switch the geyser off after use.','Contact reception if hot water is unavailable.'],
    bathtub_controls: ['Check the drain plug before filling.','Use warm water and test the temperature first.','Do not leave children unattended.','Drain the tub after use.','Contact reception if any control is unclear.'],
    safe_locker: ['Keep the safe door open while setting the code.','Enter your chosen code and confirm it.','Test the code before storing valuables.','Do not share the code.','Contact reception if the safe locks unexpectedly.'],
  },
  hi: {
    air_conditioner: ['AC रिमोट का पावर बटन दबाएँ।','Cool मोड चुनें।','तापमान 22°C से 24°C के बीच रखें।','हवा की दिशा के लिए Swing का उपयोग करें।','AC काम न करे तो रिसेप्शन से संपर्क करें।'],
    television_remote: ['टीवी और सेट-टॉप बॉक्स चालू करें।','सही HDMI/इनपुट चुनें।','रिमोट से चैनल या ऐप चुनें।','उपयोग के बाद रिमोट कमरे में रखें।','सिग्नल न हो तो रिसेप्शन से संपर्क करें।'],
    hot_water_geyser: ['ज़रूरत होने पर ही गीजर चालू करें।','पानी गर्म होने तक प्रतीक्षा करें।','तापमान सावधानी से जाँचें।','उपयोग के बाद गीजर बंद करें।','गर्म पानी न मिले तो रिसेप्शन से संपर्क करें।'],
    bathtub_controls: ['भरने से पहले ड्रेन प्लग जाँचें।','गुनगुना पानी भरें और तापमान जाँचें।','बच्चों को अकेला न छोड़ें।','उपयोग के बाद पानी निकाल दें।','किसी नियंत्रण में समस्या हो तो रिसेप्शन से संपर्क करें।'],
    safe_locker: ['कोड सेट करते समय सेफ का दरवाज़ा खुला रखें।','अपना कोड दर्ज करके पुष्टि करें।','सामान रखने से पहले कोड जाँचें।','कोड किसी से साझा न करें।','सेफ लॉक हो जाए तो रिसेप्शन से संपर्क करें।'],
  },
  mr: {
    air_conditioner: ['AC रिमोटवरील पॉवर बटण दाबा.','Cool मोड निवडा.','तापमान 22°C ते 24°C दरम्यान ठेवा.','हवेची दिशा बदलण्यासाठी Swing वापरा.','AC चालू न झाल्यास रिसेप्शनशी संपर्क करा.'],
    television_remote: ['टीव्ही आणि सेट-टॉप बॉक्स चालू करा.','योग्य HDMI/इनपुट निवडा.','रिमोटवरून चॅनेल किंवा अॅप निवडा.','वापरानंतर रिमोट खोलीतच ठेवा.','सिग्नल नसल्यास रिसेप्शनशी संपर्क करा.'],
    hot_water_geyser: ['गरज असेल तेव्हाच गीझर चालू करा.','पाणी गरम होईपर्यंत थांबा.','पाण्याचे तापमान काळजीपूर्वक तपासा.','वापरानंतर गीझर बंद करा.','गरम पाणी नसल्यास रिसेप्शनशी संपर्क करा.'],
    bathtub_controls: ['पाणी भरण्यापूर्वी ड्रेन प्लग तपासा.','कोमट पाणी भरा आणि तापमान तपासा.','लहान मुलांना एकटे सोडू नका.','वापरानंतर पाणी काढून टाका.','नियंत्रण समजत नसल्यास रिसेप्शनशी संपर्क करा.'],
    safe_locker: ['कोड सेट करताना सेफचे दार उघडे ठेवा.','आपला कोड टाकून पुष्टी करा.','मौल्यवान वस्तू ठेवण्यापूर्वी कोड तपासा.','कोड इतरांना सांगू नका.','सेफ लॉक झाल्यास रिसेप्शनशी संपर्क करा.'],
  },
  ta: {
    air_conditioner: ['AC ரிமோட்டில் பவர் பொத்தானை அழுத்தவும்.','Cool முறையைத் தேர்ந்தெடுக்கவும்.','வெப்பநிலையை 22°C முதல் 24°C வரை அமைக்கவும்.','காற்றுத் திசைக்கு Swing பயன்படுத்தவும்.','AC இயங்கவில்லை என்றால் ரிசப்ஷனை தொடர்புகொள்ளவும்.'],
    television_remote: ['டிவி மற்றும் செட்-டாப் பாக்ஸை இயக்கவும்.','சரியான HDMI/இன்புட் தேர்ந்தெடுக்கவும்.','ரிமோட்டில் சேனல் அல்லது பயன்பாட்டைத் தேர்ந்தெடுக்கவும்.','பயன்பாட்டின் பின் ரிமோட்டை அறையில் வைக்கவும்.','சிக்னல் இல்லையெனில் ரிசப்ஷனை தொடர்புகொள்ளவும்.'],
    hot_water_geyser: ['தேவையான போது மட்டும் கீசரை இயக்கவும்.','தண்ணீர் சூடாகும் வரை காத்திருக்கவும்.','வெப்பநிலையை கவனமாகச் சரிபார்க்கவும்.','பயன்பாட்டின் பின் கீசரை அணைக்கவும்.','சூடுநீர் இல்லையெனில் ரிசப்ஷனை தொடர்புகொள்ளவும்.'],
    bathtub_controls: ['நிரப்புவதற்கு முன் டிரெயின் பிளக்கைச் சரிபார்க்கவும்.','சூடான தண்ணீரை நிரப்பி வெப்பநிலையைச் சரிபார்க்கவும்.','குழந்தைகளை தனியாக விட வேண்டாம்.','பயன்பாட்டின் பின் தண்ணீரை வெளியேற்றவும்.','கட்டுப்பாடு தெளிவில்லையெனில் ரிசப்ஷனை தொடர்புகொள்ளவும்.'],
    safe_locker: ['குறியீட்டை அமைக்கும் போது கதவை திறந்தே வைத்திருக்கவும்.','உங்கள் குறியீட்டை உள்ளிட்டு உறுதிசெய்யவும்.','மதிப்புள்ள பொருட்களை வைக்கும் முன் குறியீட்டைச் சோதிக்கவும்.','குறியீட்டை பகிர வேண்டாம்.','சேஃப் பூட்டப்பட்டால் ரிசப்ஷனை தொடர்புகொள்ளவும்.'],
  },
}

export function getDirectLocaleTranslation(translations, locale) {
  if (!translations || typeof translations !== 'object') return {}
  const value = translations[locale]
  return value && typeof value === 'object' ? value : {}
}

export function getFullSectionCopy(sectionKey, locale = 'en') {
  const pack = SECTION_PACKS[locale] || EN_SECTIONS
  const fallback = EN_SECTIONS[sectionKey] || ['', '', '']
  const [label, title, subtitle] = pack[sectionKey] || fallback
  return { label, title, subtitle }
}

export function getFullItemCopy(itemKey, locale = 'en') {
  const localized = ITEM_PACKS[locale]?.[itemKey]
  const fallback = ITEM_PACKS.en[itemKey] || ['', '', '']
  const [title, description, buttonLabel] = localized || fallback
  const instructions = INSTRUCTION_PACKS[locale]?.[itemKey] || INSTRUCTION_PACKS.en[itemKey] || []
  return { title, description, button_label: buttonLabel, instructions }
}

export function supportedFullGuideLocale(locale) {
  return ['en','hi','mr','ta'].includes(locale)
}

export const FULL_GUIDE_SECTION_KEYS = SECTION_KEYS
