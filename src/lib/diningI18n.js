import { getGuideCopy } from './guestGuideI18n'

const EN = {
  "loading": "Preparing your StayQR dining experience…",
  "accessUnavailable": "Guest access unavailable",
  "accessUnavailableBody": "This food-ordering link is invalid, expired or no longer active.",
  "menuLoadFailed": "Unable to load the menu.",
  "addedToCart": "added to cart.",
  "chooseOptions": "Choose {range} option(s) for {group}.",
  "orderAlreadyReceived": "This order was already received.",
  "orderSent": "Order sent to the kitchen.",
  "cancelConfirm": "Cancel this food order?",
  "orderCancelled": "Order cancelled.",
  "unableCancel": "Unable to cancel the order.",
  "dining": "Dining",
  "guestGuide": "Guest Guide",
  "inRoomServices": "In-room Services",
  "myOrders": "My Orders",
  "secureHotelDining": "Secure hotel dining",
  "roomLinked": "Your order is linked only to Room {room} and your active stay.",
  "poweredSecurelyBy": "Powered securely by",
  "backToGuestGuide": "Back to Guest Guide",
  "room": "Room",
  "stayActive": "Stay Active",
  "stayqrDining": "StayQR Dining",
  "diningDelivered": "Hotel dining delivered directly to your room.",
  "approx": "Approx.",
  "min": "min",
  "secureOrdering": "Secure ordering",
  "liveKitchenTracking": "Live kitchen tracking",
  "language": "Language",
  "all": "All",
  "featured": "Featured",
  "curatedForStay": "Curated for your stay",
  "inRoomDiningMenu": "In-room dining menu",
  "featuredForYou": "Featured for You",
  "exploreMenu": "Explore the Menu",
  "available": "available",
  "noItemsTitle": "No items are available in this category.",
  "noItemsBody": "Please select another category or contact the hotel team.",
  "customisable": "Customisable",
  "hotelMenu": "Hotel menu",
  "preparedFresh": "Prepared fresh by the hotel kitchen.",
  "tax": "tax",
  "included": "included",
  "extra": "extra",
  "customiseAdd": "Customise & add",
  "addToCart": "Add to cart",
  "behindEveryOrder": "Behind every order",
  "kitchenCares": "A kitchen that cares.",
  "kitchenStoryBody": "Fresh preparation, hygienic handling and live status updates until the order reaches your room.",
  "watchKitchenStory": "Watch kitchen story",
  "freshlyPrepared": "Freshly prepared",
  "madeToOrder": "Made to order by the hotel kitchen.",
  "hygienicSecure": "Hygienic & secure",
  "activeRoomSecure": "Your order stays linked to the active room.",
  "liveTracking": "Live tracking",
  "liveTrackingBody": "See every kitchen status in real time.",
  "yourActiveOrder": "Your active order",
  "yourCart": "Your Cart",
  "cartEmpty": "Your cart is empty",
  "cartEmptyBody": "Select menu items to begin your room-dining order.",
  "itemSubtotal": "Item subtotal",
  "addOns": "Add-ons",
  "taxes": "Taxes",
  "total": "Total",
  "secureOrderFromRoom": "Secure order from Room {room} and your active stay.",
  "placeSecureOrder": "Place secure order",
  "sendingOrder": "Sending order…",
  "continueShopping": "Continue shopping",
  "yourOrders": "Your Orders",
  "orderSingular": "order",
  "orderPlural": "orders",
  "noOrders": "No food orders have been placed during this stay.",
  "estimatedDelivery": "Estimated delivery",
  "cancelOrder": "Cancel order",
  "thisOrderCancelled": "This order was cancelled.",
  "kitchenMessages": "Kitchen messages",
  "latestUpdates": "Latest Updates",
  "secureGuestExperience": "Secure hotel guest experience",
  "customiseOrder": "Customise your order",
  "required": "Required",
  "optional": "Optional",
  "choose": "choose",
  "optionSingular": "option",
  "optionPlural": "options",
  "includedPrice": "Included",
  "dueNow": "Due now",
  "minuteSingular": "minute",
  "minutePlural": "minutes",
  "statusPending": "pending",
  "statusAccepted": "accepted",
  "statusPreparing": "preparing",
  "statusReady": "ready",
  "statusOutForDelivery": "out for delivery",
  "statusDelivered": "delivered",
  "statusCancelled": "cancelled",
  "offerCtaDefault": "View offer",
  "offerBadgeDefault": "Limited Offer",
  "offerTitleDefault": "Make Your Stay More Rewarding",
  "offerDescriptionDefault": "Ask reception about today’s guest benefit.",
  "saveOffer": "Save offer",
  "publishOffer": "Save & publish offer"
}

const OVERRIDES = {
  "hi": {
    "loading": "आपका StayQR डाइनिंग अनुभव तैयार किया जा रहा है…",
    "accessUnavailable": "गेस्ट एक्सेस उपलब्ध नहीं है",
    "accessUnavailableBody": "यह फूड ऑर्डरिंग लिंक अमान्य, समाप्त या अब सक्रिय नहीं है।",
    "menuLoadFailed": "मेन्यू लोड नहीं हो सका।",
    "addedToCart": "कार्ट में जोड़ा गया।",
    "chooseOptions": "{group} के लिए {range} विकल्प चुनें।",
    "orderAlreadyReceived": "यह ऑर्डर पहले ही प्राप्त हो चुका है।",
    "orderSent": "ऑर्डर किचन को भेज दिया गया।",
    "cancelConfirm": "क्या यह फूड ऑर्डर रद्द करना है?",
    "orderCancelled": "ऑर्डर रद्द हो गया।",
    "unableCancel": "ऑर्डर रद्द नहीं हो सका।",
    "dining": "डाइनिंग",
    "guestGuide": "गेस्ट गाइड",
    "inRoomServices": "इन-रूम सेवाएं",
    "myOrders": "मेरे ऑर्डर",
    "secureHotelDining": "सुरक्षित होटल डाइनिंग",
    "roomLinked": "आपका ऑर्डर केवल कमरा {room} और आपके सक्रिय प्रवास से जुड़ा है।",
    "poweredSecurelyBy": "सुरक्षित रूप से संचालित",
    "backToGuestGuide": "गेस्ट गाइड पर वापस जाएं",
    "room": "कमरा",
    "stayActive": "प्रवास सक्रिय",
    "stayqrDining": "StayQR डाइनिंग",
    "diningDelivered": "होटल का भोजन सीधे आपके कमरे तक।",
    "approx": "लगभग",
    "min": "मिनट",
    "secureOrdering": "सुरक्षित ऑर्डरिंग",
    "liveKitchenTracking": "लाइव किचन ट्रैकिंग",
    "language": "भाषा",
    "all": "सभी",
    "featured": "विशेष",
    "curatedForStay": "आपके प्रवास के लिए चुना गया",
    "inRoomDiningMenu": "इन-रूम डाइनिंग मेन्यू",
    "featuredForYou": "आपके लिए विशेष",
    "exploreMenu": "मेन्यू देखें",
    "available": "उपलब्ध",
    "noItemsTitle": "इस श्रेणी में कोई आइटम उपलब्ध नहीं है।",
    "noItemsBody": "कृपया दूसरी श्रेणी चुनें या होटल टीम से संपर्क करें।",
    "customisable": "कस्टमाइज़ योग्य",
    "hotelMenu": "होटल मेन्यू",
    "preparedFresh": "होटल किचन में ताज़ा तैयार किया गया।",
    "tax": "कर",
    "included": "शामिल",
    "extra": "अतिरिक्त",
    "customiseAdd": "कस्टमाइज़ करें और जोड़ें",
    "addToCart": "कार्ट में जोड़ें",
    "behindEveryOrder": "हर ऑर्डर के पीछे",
    "kitchenCares": "एक किचन जो परवाह करता है।",
    "kitchenStoryBody": "ताज़ी तैयारी, स्वच्छ हैंडलिंग और आपके कमरे तक लाइव स्टेटस अपडेट।",
    "watchKitchenStory": "किचन स्टोरी देखें",
    "freshlyPrepared": "ताज़ा तैयार",
    "madeToOrder": "होटल किचन में ऑर्डर पर तैयार।",
    "hygienicSecure": "स्वच्छ और सुरक्षित",
    "activeRoomSecure": "ऑर्डर आपके सक्रिय कमरे से सुरक्षित रूप से जुड़ा है।",
    "liveTracking": "लाइव ट्रैकिंग",
    "liveTrackingBody": "किचन का हर स्टेटस रियल टाइम में देखें।",
    "yourActiveOrder": "आपका सक्रिय ऑर्डर",
    "yourCart": "आपका कार्ट",
    "cartEmpty": "आपका कार्ट खाली है",
    "cartEmptyBody": "रूम डाइनिंग ऑर्डर शुरू करने के लिए मेन्यू आइटम चुनें।",
    "itemSubtotal": "आइटम उप-योग",
    "addOns": "ऐड-ऑन",
    "taxes": "कर",
    "total": "कुल",
    "secureOrderFromRoom": "कमरा {room} और सक्रिय प्रवास से सुरक्षित ऑर्डर।",
    "placeSecureOrder": "सुरक्षित ऑर्डर करें",
    "sendingOrder": "ऑर्डर भेजा जा रहा है…",
    "continueShopping": "और आइटम देखें",
    "yourOrders": "आपके ऑर्डर",
    "orderSingular": "ऑर्डर",
    "orderPlural": "ऑर्डर",
    "noOrders": "इस प्रवास के दौरान कोई फूड ऑर्डर नहीं किया गया।",
    "estimatedDelivery": "अनुमानित डिलीवरी",
    "cancelOrder": "ऑर्डर रद्द करें",
    "thisOrderCancelled": "यह ऑर्डर रद्द कर दिया गया।",
    "kitchenMessages": "किचन संदेश",
    "latestUpdates": "नवीनतम अपडेट",
    "secureGuestExperience": "सुरक्षित होटल गेस्ट अनुभव",
    "customiseOrder": "अपना ऑर्डर कस्टमाइज़ करें",
    "required": "आवश्यक",
    "optional": "वैकल्पिक",
    "choose": "चुनें",
    "optionSingular": "विकल्प",
    "optionPlural": "विकल्प",
    "includedPrice": "शामिल",
    "dueNow": "अभी देय",
    "minuteSingular": "मिनट",
    "minutePlural": "मिनट",
    "statusPending": "लंबित",
    "statusAccepted": "स्वीकृत",
    "statusPreparing": "तैयार हो रहा है",
    "statusReady": "तैयार",
    "statusOutForDelivery": "रास्ते में",
    "statusDelivered": "डिलीवर हुआ",
    "statusCancelled": "रद्द",
    "offerCtaDefault": "ऑफर देखें",
    "offerBadgeDefault": "सीमित ऑफ़र",
    "offerTitleDefault": "अपने प्रवास को और खास बनाएं",
    "offerDescriptionDefault": "आज के अतिथि लाभ के बारे में रिसेप्शन से पूछें।",
    "saveOffer": "ऑफर सहेजें",
    "publishOffer": "सहेजें और प्रकाशित करें"
  },
  "mr": {
    "loading": "आपला StayQR डाइनिंग अनुभव तयार होत आहे…",
    "accessUnavailable": "अतिथी प्रवेश उपलब्ध नाही",
    "accessUnavailableBody": "ही फूड ऑर्डरिंग लिंक अवैध, कालबाह्य किंवा निष्क्रिय आहे.",
    "menuLoadFailed": "मेन्यू लोड करता आला नाही.",
    "addedToCart": "कार्टमध्ये जोडले.",
    "chooseOptions": "{group} साठी {range} पर्याय निवडा.",
    "orderAlreadyReceived": "हा ऑर्डर आधीच मिळाला आहे.",
    "orderSent": "ऑर्डर किचनकडे पाठवला.",
    "cancelConfirm": "हा फूड ऑर्डर रद्द करायचा?",
    "orderCancelled": "ऑर्डर रद्द झाला.",
    "unableCancel": "ऑर्डर रद्द करता आला नाही.",
    "dining": "डाइनिंग",
    "guestGuide": "गेस्ट गाइड",
    "inRoomServices": "रूममधील सेवा",
    "myOrders": "माझे ऑर्डर",
    "secureHotelDining": "सुरक्षित हॉटेल डाइनिंग",
    "roomLinked": "आपला ऑर्डर फक्त खोली {room} आणि सक्रिय मुक्कामाशी जोडलेला आहे.",
    "poweredSecurelyBy": "सुरक्षितपणे संचालित",
    "backToGuestGuide": "गेस्ट गाइडकडे परत",
    "room": "खोली",
    "stayActive": "मुक्काम सक्रिय",
    "stayqrDining": "StayQR डाइनिंग",
    "diningDelivered": "हॉटेलचे जेवण थेट आपल्या खोलीत.",
    "approx": "अंदाजे",
    "min": "मिनिटे",
    "secureOrdering": "सुरक्षित ऑर्डरिंग",
    "liveKitchenTracking": "लाइव्ह किचन ट्रॅकिंग",
    "language": "भाषा",
    "all": "सर्व",
    "featured": "विशेष",
    "curatedForStay": "आपल्या मुक्कामासाठी निवडलेले",
    "inRoomDiningMenu": "इन-रूम डाइनिंग मेन्यू",
    "featuredForYou": "आपल्यासाठी विशेष",
    "exploreMenu": "मेन्यू पाहा",
    "available": "उपलब्ध",
    "noItemsTitle": "या श्रेणीत कोणताही पदार्थ उपलब्ध नाही.",
    "noItemsBody": "दुसरी श्रेणी निवडा किंवा हॉटेल टीमशी संपर्क करा.",
    "customisable": "बदलता येणारे",
    "hotelMenu": "हॉटेल मेन्यू",
    "preparedFresh": "हॉटेल किचनमध्ये ताजे तयार केलेले.",
    "tax": "कर",
    "included": "समाविष्ट",
    "extra": "अतिरिक्त",
    "customiseAdd": "बदल करा आणि जोडा",
    "addToCart": "कार्टमध्ये जोडा",
    "behindEveryOrder": "प्रत्येक ऑर्डरमागे",
    "kitchenCares": "काळजी घेणारे किचन.",
    "kitchenStoryBody": "ताजी तयारी, स्वच्छ हाताळणी आणि खोलीपर्यंत लाइव्ह स्टेटस अपडेट.",
    "watchKitchenStory": "किचन स्टोरी पाहा",
    "freshlyPrepared": "ताजे तयार",
    "madeToOrder": "हॉटेल किचनमध्ये ऑर्डरनुसार तयार.",
    "hygienicSecure": "स्वच्छ आणि सुरक्षित",
    "activeRoomSecure": "ऑर्डर सक्रिय खोलीशी सुरक्षितपणे जोडलेला आहे.",
    "liveTracking": "लाइव्ह ट्रॅकिंग",
    "liveTrackingBody": "किचनचा प्रत्येक स्टेटस रिअल टाइममध्ये पाहा.",
    "yourActiveOrder": "आपला सक्रिय ऑर्डर",
    "yourCart": "आपली कार्ट",
    "cartEmpty": "आपली कार्ट रिकामी आहे",
    "cartEmptyBody": "रूम डाइनिंग ऑर्डरसाठी मेन्यूमधील पदार्थ निवडा.",
    "itemSubtotal": "पदार्थ उप-एकूण",
    "addOns": "अॅड-ऑन्स",
    "taxes": "कर",
    "total": "एकूण",
    "secureOrderFromRoom": "खोली {room} आणि सक्रिय मुक्कामातून सुरक्षित ऑर्डर.",
    "placeSecureOrder": "सुरक्षित ऑर्डर करा",
    "sendingOrder": "ऑर्डर पाठवत आहे…",
    "continueShopping": "आणखी पदार्थ पाहा",
    "yourOrders": "आपले ऑर्डर",
    "orderSingular": "ऑर्डर",
    "orderPlural": "ऑर्डर",
    "noOrders": "या मुक्कामात कोणताही फूड ऑर्डर केलेला नाही.",
    "estimatedDelivery": "अंदाजे डिलिव्हरी",
    "cancelOrder": "ऑर्डर रद्द करा",
    "thisOrderCancelled": "हा ऑर्डर रद्द केला आहे.",
    "kitchenMessages": "किचन संदेश",
    "latestUpdates": "नवीन अपडेट",
    "secureGuestExperience": "सुरक्षित हॉटेल अतिथी अनुभव",
    "customiseOrder": "आपला ऑर्डर बदला",
    "required": "आवश्यक",
    "optional": "ऐच्छिक",
    "choose": "निवडा",
    "optionSingular": "पर्याय",
    "optionPlural": "पर्याय",
    "includedPrice": "समाविष्ट",
    "dueNow": "आता देय",
    "minuteSingular": "मिनिट",
    "minutePlural": "मिनिटे",
    "statusPending": "प्रलंबित",
    "statusAccepted": "स्वीकारले",
    "statusPreparing": "तयार होत आहे",
    "statusReady": "तयार",
    "statusOutForDelivery": "मार्गावर",
    "statusDelivered": "पोहोचवले",
    "statusCancelled": "रद्द",
    "offerCtaDefault": "ऑफर पाहा",
    "offerBadgeDefault": "मर्यादित ऑफर",
    "offerTitleDefault": "तुमचा मुक्काम अधिक खास करा",
    "offerDescriptionDefault": "आजच्या अतिथी लाभाबद्दल रिसेप्शनला विचारा.",
    "saveOffer": "ऑफर जतन करा",
    "publishOffer": "जतन करून प्रकाशित करा"
  },
  "ta": {
    "loading": "உங்கள் StayQR உணவு அனுபவம் தயாராகிறது…",
    "accessUnavailable": "விருந்தினர் அணுகல் இல்லை",
    "accessUnavailableBody": "இந்த உணவு ஆர்டர் இணைப்பு செல்லாது அல்லது காலாவதியானது.",
    "menuLoadFailed": "மெனுவை ஏற்ற முடியவில்லை.",
    "addedToCart": "கார்டில் சேர்க்கப்பட்டது.",
    "chooseOptions": "{group}க்கு {range} விருப்பங்களைத் தேர்ந்தெடுக்கவும்.",
    "orderAlreadyReceived": "இந்த ஆர்டர் ஏற்கனவே பெறப்பட்டது.",
    "orderSent": "ஆர்டர் சமையலறைக்கு அனுப்பப்பட்டது.",
    "cancelConfirm": "இந்த உணவு ஆர்டரை ரத்து செய்யவா?",
    "orderCancelled": "ஆர்டர் ரத்து செய்யப்பட்டது.",
    "unableCancel": "ஆர்டரை ரத்து செய்ய முடியவில்லை.",
    "dining": "உணவகம்",
    "guestGuide": "விருந்தினர் வழிகாட்டி",
    "inRoomServices": "அறை சேவைகள்",
    "myOrders": "என் ஆர்டர்கள்",
    "secureHotelDining": "பாதுகாப்பான ஹோட்டல் உணவு",
    "roomLinked": "உங்கள் ஆர்டர் அறை {room} மற்றும் செயலில் உள்ள தங்குதலுடன் இணைக்கப்பட்டுள்ளது.",
    "poweredSecurelyBy": "பாதுகாப்பாக வழங்குவது",
    "backToGuestGuide": "விருந்தினர் வழிகாட்டிக்கு திரும்பு",
    "room": "அறை",
    "stayActive": "தங்குதல் செயலில்",
    "stayqrDining": "StayQR உணவு",
    "diningDelivered": "ஹோட்டல் உணவு நேரடியாக உங்கள் அறைக்கு.",
    "approx": "சுமார்",
    "min": "நிமி",
    "secureOrdering": "பாதுகாப்பான ஆர்டர்",
    "liveKitchenTracking": "நேரடி சமையலறை கண்காணிப்பு",
    "language": "மொழி",
    "all": "அனைத்தும்",
    "featured": "சிறப்பு",
    "curatedForStay": "உங்கள் தங்குதலுக்காக தேர்வு",
    "inRoomDiningMenu": "அறை உணவு மெனு",
    "featuredForYou": "உங்களுக்கான சிறப்பு",
    "exploreMenu": "மெனுவை பாருங்கள்",
    "available": "கிடைக்கும்",
    "noItemsTitle": "இந்த வகையில் பொருட்கள் இல்லை.",
    "noItemsBody": "வேறு வகையைத் தேர்ந்தெடுக்கவும் அல்லது ஹோட்டலை தொடர்புகொள்ளவும்.",
    "customisable": "மாற்றக்கூடியது",
    "hotelMenu": "ஹோட்டல் மெனு",
    "preparedFresh": "ஹோட்டல் சமையலறையில் புதிதாக தயாரிக்கப்பட்டது.",
    "tax": "வரி",
    "included": "உள்ளடக்கம்",
    "extra": "கூடுதல்",
    "customiseAdd": "மாற்றி சேர்க்க",
    "addToCart": "கார்டில் சேர்க்க",
    "behindEveryOrder": "ஒவ்வொரு ஆர்டரின் பின்னும்",
    "kitchenCares": "அக்கறை கொண்ட சமையலறை.",
    "kitchenStoryBody": "புதிய தயாரிப்பு, சுத்தமான கையாளுதல் மற்றும் நேரடி நிலை புதுப்பிப்புகள்.",
    "watchKitchenStory": "சமையலறை கதையை பாருங்கள்",
    "freshlyPrepared": "புதிதாக தயாரிப்பு",
    "madeToOrder": "ஆர்டருக்கு ஏற்ப தயாரிக்கப்படுகிறது.",
    "hygienicSecure": "சுத்தமும் பாதுகாப்பும்",
    "activeRoomSecure": "ஆர்டர் செயலில் உள்ள அறையுடன் இணைக்கப்பட்டுள்ளது.",
    "liveTracking": "நேரடி கண்காணிப்பு",
    "liveTrackingBody": "ஒவ்வொரு சமையலறை நிலையையும் நேரடியாக பாருங்கள்.",
    "yourActiveOrder": "உங்கள் செயலில் உள்ள ஆர்டர்",
    "yourCart": "உங்கள் கார்ட்",
    "cartEmpty": "உங்கள் கார்ட் காலியாக உள்ளது",
    "cartEmptyBody": "அறை உணவு ஆர்டருக்கு பொருட்களைத் தேர்ந்தெடுக்கவும்.",
    "itemSubtotal": "பொருள் துணை மொத்தம்",
    "addOns": "கூடுதல்",
    "taxes": "வரிகள்",
    "total": "மொத்தம்",
    "secureOrderFromRoom": "அறை {room} இலிருந்து பாதுகாப்பான ஆர்டர்.",
    "placeSecureOrder": "பாதுகாப்பாக ஆர்டர் செய்ய",
    "sendingOrder": "ஆர்டர் அனுப்பப்படுகிறது…",
    "continueShopping": "மேலும் பாருங்கள்",
    "yourOrders": "உங்கள் ஆர்டர்கள்",
    "orderSingular": "ஆர்டர்",
    "orderPlural": "ஆர்டர்கள்",
    "noOrders": "இந்த தங்குதலில் உணவு ஆர்டர் இல்லை.",
    "estimatedDelivery": "மதிப்பிடப்பட்ட டெலிவரி",
    "cancelOrder": "ஆர்டரை ரத்து செய்ய",
    "thisOrderCancelled": "இந்த ஆர்டர் ரத்து செய்யப்பட்டது.",
    "kitchenMessages": "சமையலறை செய்திகள்",
    "latestUpdates": "சமீபத்திய புதுப்பிப்புகள்",
    "secureGuestExperience": "பாதுகாப்பான ஹோட்டல் அனுபவம்",
    "customiseOrder": "உங்கள் ஆர்டரை மாற்றுங்கள்",
    "required": "தேவை",
    "optional": "விருப்பம்",
    "choose": "தேர்வு",
    "optionSingular": "விருப்பம்",
    "optionPlural": "விருப்பங்கள்",
    "includedPrice": "உள்ளடக்கம்",
    "dueNow": "இப்போது",
    "minuteSingular": "நிமிடம்",
    "minutePlural": "நிமிடங்கள்",
    "statusPending": "நிலுவையில்",
    "statusAccepted": "ஏற்றுக்கொள்ளப்பட்டது",
    "statusPreparing": "தயாராகிறது",
    "statusReady": "தயார்",
    "statusOutForDelivery": "வழியில்",
    "statusDelivered": "வழங்கப்பட்டது",
    "statusCancelled": "ரத்து",
    "offerCtaDefault": "சலுகையை பாருங்கள்",
    "offerBadgeDefault": "வரையறுக்கப்பட்ட சலுகை",
    "offerTitleDefault": "உங்கள் தங்குதலை மேலும் சிறப்பாக்குங்கள்",
    "offerDescriptionDefault": "இன்றைய விருந்தினர் சலுகை பற்றி வரவேற்பறையில் கேளுங்கள்.",
    "saveOffer": "சலுகையை சேமி",
    "publishOffer": "சேமித்து வெளியிடு"
  },
  "te": {
    "loading": "మీ StayQR డైనింగ్ అనుభవం సిద్ధమవుతోంది…",
    "accessUnavailable": "అతిథి యాక్సెస్ లేదు",
    "accessUnavailableBody": "ఈ ఫుడ్ ఆర్డరింగ్ లింక్ చెల్లదు లేదా గడువు ముగిసింది.",
    "menuLoadFailed": "మెనూ లోడ్ కాలేదు.",
    "addedToCart": "కార్ట్‌లో చేర్చబడింది.",
    "chooseOptions": "{group} కోసం {range} ఎంపికలను ఎంచుకోండి.",
    "orderAlreadyReceived": "ఈ ఆర్డర్ ఇప్పటికే అందింది.",
    "orderSent": "ఆర్డర్ కిచెన్‌కు పంపబడింది.",
    "cancelConfirm": "ఈ ఫుడ్ ఆర్డర్‌ను రద్దు చేయాలా?",
    "orderCancelled": "ఆర్డర్ రద్దయింది.",
    "unableCancel": "ఆర్డర్ రద్దు కాలేదు.",
    "dining": "డైనింగ్",
    "guestGuide": "అతిథి గైడ్",
    "inRoomServices": "గది సేవలు",
    "myOrders": "నా ఆర్డర్లు",
    "secureHotelDining": "సురక్షిత హోటల్ డైనింగ్",
    "roomLinked": "మీ ఆర్డర్ గది {room} మరియు సక్రియ బసకు మాత్రమే అనుసంధానించబడింది.",
    "poweredSecurelyBy": "సురక్షితంగా అందించేది",
    "backToGuestGuide": "అతిథి గైడ్‌కు తిరిగి",
    "room": "గది",
    "stayActive": "బస సక్రియం",
    "stayqrDining": "StayQR డైనింగ్",
    "diningDelivered": "హోటల్ భోజనం నేరుగా మీ గదికి.",
    "approx": "సుమారు",
    "min": "నిమి",
    "secureOrdering": "సురక్షిత ఆర్డరింగ్",
    "liveKitchenTracking": "లైవ్ కిచెన్ ట్రాకింగ్",
    "language": "భాష",
    "all": "అన్నీ",
    "featured": "ప్రత్యేకం",
    "curatedForStay": "మీ బస కోసం ఎంపిక",
    "inRoomDiningMenu": "గది డైనింగ్ మెనూ",
    "featuredForYou": "మీ కోసం ప్రత్యేకం",
    "exploreMenu": "మెనూ చూడండి",
    "available": "అందుబాటులో",
    "noItemsTitle": "ఈ విభాగంలో ఐటమ్స్ లేవు.",
    "noItemsBody": "మరో విభాగాన్ని ఎంచుకోండి లేదా హోటల్‌ను సంప్రదించండి.",
    "customisable": "మార్చుకోగలది",
    "hotelMenu": "హోటల్ మెనూ",
    "preparedFresh": "హోటల్ కిచెన్‌లో తాజాగా తయారు చేస్తారు.",
    "tax": "పన్ను",
    "included": "చేర్చబడింది",
    "extra": "అదనంగా",
    "customiseAdd": "మార్చి చేర్చండి",
    "addToCart": "కార్ట్‌లో చేర్చండి",
    "behindEveryOrder": "ప్రతి ఆర్డర్ వెనుక",
    "kitchenCares": "శ్రద్ధగల కిచెన్.",
    "kitchenStoryBody": "తాజా తయారీ, పరిశుభ్రమైన నిర్వహణ మరియు లైవ్ అప్‌డేట్స్.",
    "watchKitchenStory": "కిచెన్ కథ చూడండి",
    "freshlyPrepared": "తాజాగా తయారు",
    "madeToOrder": "ఆర్డర్‌కు అనుగుణంగా తయారు.",
    "hygienicSecure": "పరిశుభ్రం మరియు సురక్షితం",
    "activeRoomSecure": "ఆర్డర్ సక్రియ గదికి అనుసంధానం.",
    "liveTracking": "లైవ్ ట్రాకింగ్",
    "liveTrackingBody": "ప్రతి కిచెన్ స్థితిని ప్రత్యక్షంగా చూడండి.",
    "yourActiveOrder": "మీ సక్రియ ఆర్డర్",
    "yourCart": "మీ కార్ట్",
    "cartEmpty": "మీ కార్ట్ ఖాళీగా ఉంది",
    "cartEmptyBody": "గది డైనింగ్ కోసం ఐటమ్స్ ఎంచుకోండి.",
    "itemSubtotal": "ఐటమ్ ఉపమొత్తం",
    "addOns": "అడ్-ఆన్స్",
    "taxes": "పన్నులు",
    "total": "మొత్తం",
    "secureOrderFromRoom": "గది {room} నుండి సురక్షిత ఆర్డర్.",
    "placeSecureOrder": "సురక్షిత ఆర్డర్ చేయండి",
    "sendingOrder": "ఆర్డర్ పంపుతోంది…",
    "continueShopping": "మరిన్ని చూడండి",
    "yourOrders": "మీ ఆర్డర్లు",
    "orderSingular": "ఆర్డర్",
    "orderPlural": "ఆర్డర్లు",
    "noOrders": "ఈ బసలో ఫుడ్ ఆర్డర్లు లేవు.",
    "estimatedDelivery": "అంచనా డెలివరీ",
    "cancelOrder": "ఆర్డర్ రద్దు",
    "thisOrderCancelled": "ఈ ఆర్డర్ రద్దయింది.",
    "kitchenMessages": "కిచెన్ సందేశాలు",
    "latestUpdates": "తాజా అప్‌డేట్స్",
    "secureGuestExperience": "సురక్షిత హోటల్ అనుభవం",
    "customiseOrder": "మీ ఆర్డర్ మార్చండి",
    "required": "తప్పనిసరి",
    "optional": "ఐచ్ఛికం",
    "choose": "ఎంచుకోండి",
    "optionSingular": "ఎంపిక",
    "optionPlural": "ఎంపికలు",
    "includedPrice": "చేర్చబడింది",
    "dueNow": "ఇప్పుడే",
    "minuteSingular": "నిమిషం",
    "minutePlural": "నిమిషాలు",
    "statusPending": "పెండింగ్",
    "statusAccepted": "అంగీకరించారు",
    "statusPreparing": "తయారవుతోంది",
    "statusReady": "సిద్ధం",
    "statusOutForDelivery": "మార్గంలో",
    "statusDelivered": "డెలివర్ అయింది",
    "statusCancelled": "రద్దు",
    "offerCtaDefault": "ఆఫర్ చూడండి",
    "offerBadgeDefault": "పరిమిత ఆఫర్",
    "offerTitleDefault": "మీ బసను మరింత ప్రత్యేకంగా మార్చుకోండి",
    "offerDescriptionDefault": "ఈ రోజు అతిథి ప్రయోజనం గురించి రిసెప్షన్‌ను అడగండి.",
    "saveOffer": "ఆఫర్ సేవ్ చేయండి",
    "publishOffer": "సేవ్ చేసి ప్రచురించండి"
  },
  "bn": {
    "loading": "আপনার StayQR ডাইনিং অভিজ্ঞতা প্রস্তুত হচ্ছে…",
    "accessUnavailable": "অতিথি অ্যাক্সেস নেই",
    "accessUnavailableBody": "এই খাবার অর্ডার লিংকটি অবৈধ বা মেয়াদোত্তীর্ণ।",
    "menuLoadFailed": "মেনু লোড করা যায়নি।",
    "addedToCart": "কার্টে যোগ হয়েছে।",
    "chooseOptions": "{group}-এর জন্য {range}টি বিকল্প বেছে নিন।",
    "orderAlreadyReceived": "এই অর্ডারটি ইতিমধ্যে পাওয়া গেছে।",
    "orderSent": "অর্ডার রান্নাঘরে পাঠানো হয়েছে।",
    "cancelConfirm": "এই খাবারের অর্ডার বাতিল করবেন?",
    "orderCancelled": "অর্ডার বাতিল হয়েছে।",
    "unableCancel": "অর্ডার বাতিল করা যায়নি।",
    "dining": "ডাইনিং",
    "guestGuide": "গেস্ট গাইড",
    "inRoomServices": "রুম সার্ভিস",
    "myOrders": "আমার অর্ডার",
    "secureHotelDining": "নিরাপদ হোটেল ডাইনিং",
    "roomLinked": "আপনার অর্ডার শুধু রুম {room} ও সক্রিয় থাকার সঙ্গে যুক্ত।",
    "poweredSecurelyBy": "নিরাপদভাবে পরিচালিত",
    "backToGuestGuide": "গেস্ট গাইডে ফিরুন",
    "room": "রুম",
    "stayActive": "থাকা সক্রিয়",
    "stayqrDining": "StayQR ডাইনিং",
    "diningDelivered": "হোটেলের খাবার সরাসরি আপনার রুমে।",
    "approx": "প্রায়",
    "min": "মিনিট",
    "secureOrdering": "নিরাপদ অর্ডারিং",
    "liveKitchenTracking": "লাইভ কিচেন ট্র্যাকিং",
    "language": "ভাষা",
    "all": "সব",
    "featured": "বিশেষ",
    "curatedForStay": "আপনার থাকার জন্য বাছাই",
    "inRoomDiningMenu": "ইন-রুম ডাইনিং মেনু",
    "featuredForYou": "আপনার জন্য বিশেষ",
    "exploreMenu": "মেনু দেখুন",
    "available": "উপলব্ধ",
    "noItemsTitle": "এই বিভাগে কোনো আইটেম নেই।",
    "noItemsBody": "অন্য বিভাগ বেছে নিন বা হোটেল টিমকে জানান।",
    "customisable": "পরিবর্তনযোগ্য",
    "hotelMenu": "হোটেল মেনু",
    "preparedFresh": "হোটেল রান্নাঘরে তাজা তৈরি।",
    "tax": "কর",
    "included": "অন্তর্ভুক্ত",
    "extra": "অতিরিক্ত",
    "customiseAdd": "পরিবর্তন করে যোগ করুন",
    "addToCart": "কার্টে যোগ করুন",
    "behindEveryOrder": "প্রতিটি অর্ডারের পেছনে",
    "kitchenCares": "যত্নশীল একটি রান্নাঘর।",
    "kitchenStoryBody": "তাজা প্রস্তুতি, পরিচ্ছন্ন ব্যবস্থাপনা ও লাইভ আপডেট।",
    "watchKitchenStory": "কিচেন স্টোরি দেখুন",
    "freshlyPrepared": "তাজা প্রস্তুত",
    "madeToOrder": "অর্ডার অনুযায়ী তৈরি।",
    "hygienicSecure": "পরিচ্ছন্ন ও নিরাপদ",
    "activeRoomSecure": "অর্ডার সক্রিয় রুমের সঙ্গে যুক্ত।",
    "liveTracking": "লাইভ ট্র্যাকিং",
    "liveTrackingBody": "প্রতিটি রান্নাঘরের অবস্থা লাইভ দেখুন।",
    "yourActiveOrder": "আপনার সক্রিয় অর্ডার",
    "yourCart": "আপনার কার্ট",
    "cartEmpty": "আপনার কার্ট খালি",
    "cartEmptyBody": "রুম ডাইনিংয়ের জন্য আইটেম বেছে নিন।",
    "itemSubtotal": "আইটেম উপমোট",
    "addOns": "অ্যাড-অন",
    "taxes": "কর",
    "total": "মোট",
    "secureOrderFromRoom": "রুম {room} থেকে নিরাপদ অর্ডার।",
    "placeSecureOrder": "নিরাপদ অর্ডার করুন",
    "sendingOrder": "অর্ডার পাঠানো হচ্ছে…",
    "continueShopping": "আরও দেখুন",
    "yourOrders": "আপনার অর্ডার",
    "orderSingular": "অর্ডার",
    "orderPlural": "অর্ডার",
    "noOrders": "এই থাকার সময় কোনো খাবার অর্ডার করা হয়নি।",
    "estimatedDelivery": "আনুমানিক ডেলিভারি",
    "cancelOrder": "অর্ডার বাতিল",
    "thisOrderCancelled": "এই অর্ডারটি বাতিল হয়েছে।",
    "kitchenMessages": "রান্নাঘরের বার্তা",
    "latestUpdates": "সর্বশেষ আপডেট",
    "secureGuestExperience": "নিরাপদ হোটেল অভিজ্ঞতা",
    "customiseOrder": "আপনার অর্ডার পরিবর্তন করুন",
    "required": "আবশ্যক",
    "optional": "ঐচ্ছিক",
    "choose": "বেছে নিন",
    "optionSingular": "বিকল্প",
    "optionPlural": "বিকল্প",
    "includedPrice": "অন্তর্ভুক্ত",
    "dueNow": "এখনই",
    "minuteSingular": "মিনিট",
    "minutePlural": "মিনিট",
    "statusPending": "অপেক্ষমাণ",
    "statusAccepted": "গৃহীত",
    "statusPreparing": "প্রস্তুত হচ্ছে",
    "statusReady": "প্রস্তুত",
    "statusOutForDelivery": "পথে",
    "statusDelivered": "ডেলিভার হয়েছে",
    "statusCancelled": "বাতিল",
    "offerCtaDefault": "অফার দেখুন",
    "offerBadgeDefault": "সীমিত অফার",
    "offerTitleDefault": "আপনার থাকা আরও বিশেষ করুন",
    "offerDescriptionDefault": "আজকের অতিথি সুবিধা সম্পর্কে রিসেপশনে জিজ্ঞাসা করুন।",
    "saveOffer": "অফার সংরক্ষণ",
    "publishOffer": "সংরক্ষণ ও প্রকাশ"
  },
  "gu": {
    "loading": "તમારો StayQR ડાઇનિંગ અનુભવ તૈયાર થઈ રહ્યો છે…",
    "accessUnavailable": "મહેમાન પ્રવેશ ઉપલબ્ધ નથી",
    "accessUnavailableBody": "આ ફૂડ ઓર્ડર લિંક અમાન્ય અથવા સમયસમાપ્ત છે.",
    "menuLoadFailed": "મેનુ લોડ થઈ શક્યું નથી.",
    "addedToCart": "કાર્ટમાં ઉમેરાયું.",
    "chooseOptions": "{group} માટે {range} વિકલ્પ પસંદ કરો.",
    "orderAlreadyReceived": "આ ઓર્ડર પહેલેથી મળ્યો છે.",
    "orderSent": "ઓર્ડર કિચનમાં મોકલાયો.",
    "cancelConfirm": "આ ફૂડ ઓર્ડર રદ કરવો?",
    "orderCancelled": "ઓર્ડર રદ થયો.",
    "unableCancel": "ઓર્ડર રદ થઈ શક્યો નથી.",
    "dining": "ડાઇનિંગ",
    "guestGuide": "ગેસ્ટ ગાઇડ",
    "inRoomServices": "રૂમ સેવાઓ",
    "myOrders": "મારા ઓર્ડર",
    "secureHotelDining": "સુરક્ષિત હોટેલ ડાઇનિંગ",
    "roomLinked": "તમારો ઓર્ડર માત્ર રૂમ {room} અને સક્રિય રોકાણ સાથે જોડાયેલ છે.",
    "poweredSecurelyBy": "સુરક્ષિત રીતે સંચાલિત",
    "backToGuestGuide": "ગેસ્ટ ગાઇડ પર પાછા",
    "room": "રૂમ",
    "stayActive": "રોકાણ સક્રિય",
    "stayqrDining": "StayQR ડાઇનિંગ",
    "diningDelivered": "હોટેલ ભોજન સીધું તમારા રૂમમાં.",
    "approx": "આશરે",
    "min": "મિનિટ",
    "secureOrdering": "સુરક્ષિત ઓર્ડરિંગ",
    "liveKitchenTracking": "લાઇવ કિચન ટ્રેકિંગ",
    "language": "ભાષા",
    "all": "બધું",
    "featured": "વિશેષ",
    "curatedForStay": "તમારા રોકાણ માટે પસંદ",
    "inRoomDiningMenu": "ઇન-રૂમ ડાઇનિંગ મેનુ",
    "featuredForYou": "તમારા માટે વિશેષ",
    "exploreMenu": "મેનુ જુઓ",
    "available": "ઉપલબ્ધ",
    "noItemsTitle": "આ શ્રેણીમાં કોઈ વસ્તુ ઉપલબ્ધ નથી.",
    "noItemsBody": "બીજી શ્રેણી પસંદ કરો અથવા હોટેલને સંપર્ક કરો.",
    "customisable": "બદલી શકાય",
    "hotelMenu": "હોટેલ મેનુ",
    "preparedFresh": "હોટેલ કિચનમાં તાજું બનાવેલું.",
    "tax": "કર",
    "included": "સમાવેશિત",
    "extra": "વધારાનું",
    "customiseAdd": "બદલો અને ઉમેરો",
    "addToCart": "કાર્ટમાં ઉમેરો",
    "behindEveryOrder": "દરેક ઓર્ડર પાછળ",
    "kitchenCares": "કાળજી લેતું કિચન.",
    "kitchenStoryBody": "તાજી તૈયારી, સ્વચ્છ હેન્ડલિંગ અને લાઇવ અપડેટ.",
    "watchKitchenStory": "કિચન સ્ટોરી જુઓ",
    "freshlyPrepared": "તાજું તૈયાર",
    "madeToOrder": "ઓર્ડર મુજબ તૈયાર.",
    "hygienicSecure": "સ્વચ્છ અને સુરક્ષિત",
    "activeRoomSecure": "ઓર્ડર સક્રિય રૂમ સાથે સુરક્ષિત રીતે જોડાયેલ છે.",
    "liveTracking": "લાઇવ ટ્રેકિંગ",
    "liveTrackingBody": "દરેક કિચન સ્થિતિ લાઇવ જુઓ.",
    "yourActiveOrder": "તમારો સક્રિય ઓર્ડર",
    "yourCart": "તમારું કાર્ટ",
    "cartEmpty": "તમારું કાર્ટ ખાલી છે",
    "cartEmptyBody": "રૂમ ડાઇનિંગ માટે વસ્તુઓ પસંદ કરો.",
    "itemSubtotal": "વસ્તુ ઉપકુલ",
    "addOns": "એડ-ઓન",
    "taxes": "કર",
    "total": "કુલ",
    "secureOrderFromRoom": "રૂમ {room}માંથી સુરક્ષિત ઓર્ડર.",
    "placeSecureOrder": "સુરક્ષિત ઓર્ડર કરો",
    "sendingOrder": "ઓર્ડર મોકલાઈ રહ્યો છે…",
    "continueShopping": "વધુ જુઓ",
    "yourOrders": "તમારા ઓર્ડર",
    "orderSingular": "ઓર્ડર",
    "orderPlural": "ઓર્ડર",
    "noOrders": "આ રોકાણ દરમિયાન કોઈ ફૂડ ઓર્ડર નથી.",
    "estimatedDelivery": "અંદાજિત ડિલિવરી",
    "cancelOrder": "ઓર્ડર રદ કરો",
    "thisOrderCancelled": "આ ઓર્ડર રદ થયો છે.",
    "kitchenMessages": "કિચન સંદેશા",
    "latestUpdates": "તાજા અપડેટ",
    "secureGuestExperience": "સુરક્ષિત હોટેલ અનુભવ",
    "customiseOrder": "તમારો ઓર્ડર બદલો",
    "required": "જરૂરી",
    "optional": "વૈકલ્પિક",
    "choose": "પસંદ કરો",
    "optionSingular": "વિકલ્પ",
    "optionPlural": "વિકલ્પો",
    "includedPrice": "સમાવેશિત",
    "dueNow": "હમણાં",
    "minuteSingular": "મિનિટ",
    "minutePlural": "મિનિટ",
    "statusPending": "બાકી",
    "statusAccepted": "સ્વીકાર્યું",
    "statusPreparing": "તૈયાર થઈ રહ્યું છે",
    "statusReady": "તૈયાર",
    "statusOutForDelivery": "રસ્તામાં",
    "statusDelivered": "પહોંચાડ્યું",
    "statusCancelled": "રદ",
    "offerCtaDefault": "ઓફર જુઓ",
    "offerBadgeDefault": "મર્યાદિત ઓફર",
    "offerTitleDefault": "તમારા રોકાણને વધુ ખાસ બનાવો",
    "offerDescriptionDefault": "આજના મહેમાન લાભ વિશે રિસેપ્શનને પૂછો.",
    "saveOffer": "ઓફર સાચવો",
    "publishOffer": "સાચવો અને પ્રકાશિત કરો"
  },
  "kn": {
    "loading": "ನಿಮ್ಮ StayQR ಡೈನಿಂಗ್ ಅನುಭವ ಸಿದ್ಧವಾಗುತ್ತಿದೆ…",
    "accessUnavailable": "ಅತಿಥಿ ಪ್ರವೇಶ ಲಭ್ಯವಿಲ್ಲ",
    "accessUnavailableBody": "ಈ ಆಹಾರ ಆರ್ಡರ್ ಲಿಂಕ್ ಅಮಾನ್ಯ ಅಥವಾ ಅವಧಿ ಮುಗಿದಿದೆ.",
    "menuLoadFailed": "ಮೆನು ಲೋಡ್ ಆಗಲಿಲ್ಲ.",
    "addedToCart": "ಕಾರ್ಟ್‌ಗೆ ಸೇರಿಸಲಾಗಿದೆ.",
    "chooseOptions": "{group}ಗಾಗಿ {range} ಆಯ್ಕೆಗಳನ್ನು ಆರಿಸಿ.",
    "orderAlreadyReceived": "ಈ ಆರ್ಡರ್ ಈಗಾಗಲೇ ಬಂದಿದೆ.",
    "orderSent": "ಆರ್ಡರ್ ಅಡುಗೆಮನೆಗೆ ಕಳುಹಿಸಲಾಗಿದೆ.",
    "cancelConfirm": "ಈ ಆಹಾರ ಆರ್ಡರ್ ರದ್ದು ಮಾಡಬೇಕೆ?",
    "orderCancelled": "ಆರ್ಡರ್ ರದ್ದಾಗಿದೆ.",
    "unableCancel": "ಆರ್ಡರ್ ರದ್ದು ಆಗಲಿಲ್ಲ.",
    "dining": "ಡೈನಿಂಗ್",
    "guestGuide": "ಅತಿಥಿ ಗೈಡ್",
    "inRoomServices": "ಕೊಠಡಿ ಸೇವೆಗಳು",
    "myOrders": "ನನ್ನ ಆರ್ಡರ್‌ಗಳು",
    "secureHotelDining": "ಸುರಕ್ಷಿತ ಹೋಟೆಲ್ ಡೈನಿಂಗ್",
    "roomLinked": "ನಿಮ್ಮ ಆರ್ಡರ್ ಕೊಠಡಿ {room} ಮತ್ತು ಸಕ್ರಿಯ ವಾಸ್ತವ್ಯಕ್ಕೆ ಮಾತ್ರ ಸಂಪರ್ಕಿತವಾಗಿದೆ.",
    "poweredSecurelyBy": "ಸುರಕ್ಷಿತವಾಗಿ ಒದಗಿಸುವುದು",
    "backToGuestGuide": "ಅತಿಥಿ ಗೈಡ್‌ಗೆ ಹಿಂತಿರುಗಿ",
    "room": "ಕೊಠಡಿ",
    "stayActive": "ವಾಸ್ತವ್ಯ ಸಕ್ರಿಯ",
    "stayqrDining": "StayQR ಡೈನಿಂಗ್",
    "diningDelivered": "ಹೋಟೆಲ್ ಊಟ ನೇರವಾಗಿ ನಿಮ್ಮ ಕೊಠಡಿಗೆ.",
    "approx": "ಸುಮಾರು",
    "min": "ನಿಮಿಷ",
    "secureOrdering": "ಸುರಕ್ಷಿತ ಆರ್ಡರಿಂಗ್",
    "liveKitchenTracking": "ಲೈವ್ ಕಿಚನ್ ಟ್ರ್ಯಾಕಿಂಗ್",
    "language": "ಭಾಷೆ",
    "all": "ಎಲ್ಲ",
    "featured": "ವಿಶೇಷ",
    "curatedForStay": "ನಿಮ್ಮ ವಾಸ್ತವ್ಯಕ್ಕಾಗಿ ಆಯ್ಕೆ",
    "inRoomDiningMenu": "ಕೊಠಡಿ ಡೈನಿಂಗ್ ಮೆನು",
    "featuredForYou": "ನಿಮಗಾಗಿ ವಿಶೇಷ",
    "exploreMenu": "ಮೆನು ನೋಡಿ",
    "available": "ಲಭ್ಯ",
    "noItemsTitle": "ಈ ವರ್ಗದಲ್ಲಿ ಐಟಂಗಳು ಲಭ್ಯವಿಲ್ಲ.",
    "noItemsBody": "ಮತ್ತೊಂದು ವರ್ಗ ಆಯ್ಕೆ ಮಾಡಿ ಅಥವಾ ಹೋಟೆಲ್ ಸಂಪರ್ಕಿಸಿ.",
    "customisable": "ಬದಲಾಯಿಸಬಹುದಾದ",
    "hotelMenu": "ಹೋಟೆಲ್ ಮೆನು",
    "preparedFresh": "ಹೋಟೆಲ್ ಅಡುಗೆಮನೆಯಲ್ಲಿ ತಾಜಾಗಿ ತಯಾರಿಸಲಾಗಿದೆ.",
    "tax": "ತೆರಿಗೆ",
    "included": "ಒಳಗೊಂಡಿದೆ",
    "extra": "ಹೆಚ್ಚುವರಿ",
    "customiseAdd": "ಬದಲಿಸಿ ಸೇರಿಸಿ",
    "addToCart": "ಕಾರ್ಟ್‌ಗೆ ಸೇರಿಸಿ",
    "behindEveryOrder": "ಪ್ರತಿ ಆರ್ಡರ್ ಹಿಂದೆ",
    "kitchenCares": "ಕಾಳಜಿ ವಹಿಸುವ ಅಡುಗೆಮನೆ.",
    "kitchenStoryBody": "ತಾಜಾ ತಯಾರಿ, ಸ್ವಚ್ಛ ನಿರ್ವಹಣೆ ಮತ್ತು ಲೈವ್ ಅಪ್ಡೇಟ್‌ಗಳು.",
    "watchKitchenStory": "ಕಿಚನ್ ಕಥೆ ನೋಡಿ",
    "freshlyPrepared": "ತಾಜಾಗಿ ತಯಾರಿಸಿದ",
    "madeToOrder": "ಆರ್ಡರ್‌ಗೆ ತಯಾರಿಸಲಾಗುತ್ತದೆ.",
    "hygienicSecure": "ಸ್ವಚ್ಛ ಮತ್ತು ಸುರಕ್ಷಿತ",
    "activeRoomSecure": "ಆರ್ಡರ್ ಸಕ್ರಿಯ ಕೊಠಡಿಗೆ ಸಂಪರ್ಕಿತವಾಗಿದೆ.",
    "liveTracking": "ಲೈವ್ ಟ್ರ್ಯಾಕಿಂಗ್",
    "liveTrackingBody": "ಪ್ರತಿ ಕಿಚನ್ ಸ್ಥಿತಿಯನ್ನು ಲೈವ್ ನೋಡಿ.",
    "yourActiveOrder": "ನಿಮ್ಮ ಸಕ್ರಿಯ ಆರ್ಡರ್",
    "yourCart": "ನಿಮ್ಮ ಕಾರ್ಟ್",
    "cartEmpty": "ನಿಮ್ಮ ಕಾರ್ಟ್ ಖಾಲಿಯಾಗಿದೆ",
    "cartEmptyBody": "ಕೊಠಡಿ ಊಟಕ್ಕಾಗಿ ಐಟಂಗಳನ್ನು ಆಯ್ಕೆ ಮಾಡಿ.",
    "itemSubtotal": "ಐಟಂ ಉಪಮೊತ್ತ",
    "addOns": "ಆಡ್-ಆನ್‌ಗಳು",
    "taxes": "ತೆರಿಗೆಗಳು",
    "total": "ಒಟ್ಟು",
    "secureOrderFromRoom": "ಕೊಠಡಿ {room}ಯಿಂದ ಸುರಕ್ಷಿತ ಆರ್ಡರ್.",
    "placeSecureOrder": "ಸುರಕ್ಷಿತ ಆರ್ಡರ್ ಮಾಡಿ",
    "sendingOrder": "ಆರ್ಡರ್ ಕಳುಹಿಸಲಾಗುತ್ತಿದೆ…",
    "continueShopping": "ಇನ್ನಷ್ಟು ನೋಡಿ",
    "yourOrders": "ನಿಮ್ಮ ಆರ್ಡರ್‌ಗಳು",
    "orderSingular": "ಆರ್ಡರ್",
    "orderPlural": "ಆರ್ಡರ್‌ಗಳು",
    "noOrders": "ಈ ವಾಸ್ತವ್ಯದಲ್ಲಿ ಆಹಾರ ಆರ್ಡರ್ ಇಲ್ಲ.",
    "estimatedDelivery": "ಅಂದಾಜು ವಿತರಣೆ",
    "cancelOrder": "ಆರ್ಡರ್ ರದ್ದು ಮಾಡಿ",
    "thisOrderCancelled": "ಈ ಆರ್ಡರ್ ರದ್ದಾಗಿದೆ.",
    "kitchenMessages": "ಕಿಚನ್ ಸಂದೇಶಗಳು",
    "latestUpdates": "ಹೊಸ ಅಪ್ಡೇಟ್‌ಗಳು",
    "secureGuestExperience": "ಸುರಕ್ಷಿತ ಹೋಟೆಲ್ ಅನುಭವ",
    "customiseOrder": "ನಿಮ್ಮ ಆರ್ಡರ್ ಬದಲಿಸಿ",
    "required": "ಅಗತ್ಯ",
    "optional": "ಐಚ್ಛಿಕ",
    "choose": "ಆಯ್ಕೆ ಮಾಡಿ",
    "optionSingular": "ಆಯ್ಕೆ",
    "optionPlural": "ಆಯ್ಕೆಗಳು",
    "includedPrice": "ಒಳಗೊಂಡಿದೆ",
    "dueNow": "ಈಗ",
    "minuteSingular": "ನಿಮಿಷ",
    "minutePlural": "ನಿಮಿಷಗಳು",
    "statusPending": "ಬಾಕಿ",
    "statusAccepted": "ಸ್ವೀಕರಿಸಲಾಗಿದೆ",
    "statusPreparing": "ತಯಾರಾಗುತ್ತಿದೆ",
    "statusReady": "ಸಿದ್ಧ",
    "statusOutForDelivery": "ಮಾರ್ಗದಲ್ಲಿ",
    "statusDelivered": "ತಲುಪಿಸಲಾಗಿದೆ",
    "statusCancelled": "ರದ್ದು",
    "offerCtaDefault": "ಆಫರ್ ನೋಡಿ",
    "offerBadgeDefault": "ಸೀಮಿತ ಆಫರ್",
    "offerTitleDefault": "ನಿಮ್ಮ ವಾಸ್ತವ್ಯವನ್ನು ಇನ್ನಷ್ಟು ವಿಶೇಷಗೊಳಿಸಿ",
    "offerDescriptionDefault": "ಇಂದಿನ ಅತಿಥಿ ಪ್ರಯೋಜನದ ಬಗ್ಗೆ ರಿಸೆಪ್ಶನ್‌ನಲ್ಲಿ ಕೇಳಿ.",
    "saveOffer": "ಆಫರ್ ಉಳಿಸಿ",
    "publishOffer": "ಉಳಿಸಿ ಪ್ರಕಟಿಸಿ"
  },
  "ml": {
    "loading": "നിങ്ങളുടെ StayQR ഡൈനിംഗ് അനുഭവം തയ്യാറാകുന്നു…",
    "accessUnavailable": "അതിഥി പ്രവേശനം ലഭ്യമല്ല",
    "accessUnavailableBody": "ഈ ഭക്ഷണ ഓർഡർ ലിങ്ക് അസാധുവോ കാലഹരണപ്പെട്ടതോ ആണ്.",
    "menuLoadFailed": "മെനു ലോഡ് ചെയ്യാനായില്ല.",
    "addedToCart": "കാർട്ടിൽ ചേർത്തു.",
    "chooseOptions": "{group}ക്കായി {range} ഓപ്ഷനുകൾ തിരഞ്ഞെടുക്കുക.",
    "orderAlreadyReceived": "ഈ ഓർഡർ ഇതിനകം ലഭിച്ചിട്ടുണ്ട്.",
    "orderSent": "ഓർഡർ അടുക്കളയിലേക്ക് അയച്ചു.",
    "cancelConfirm": "ഈ ഭക്ഷണ ഓർഡർ റദ്ദാക്കണോ?",
    "orderCancelled": "ഓർഡർ റദ്ദാക്കി.",
    "unableCancel": "ഓർഡർ റദ്ദാക്കാനായില്ല.",
    "dining": "ഡൈനിംഗ്",
    "guestGuide": "ഗസ്റ്റ് ഗൈഡ്",
    "inRoomServices": "റൂം സേവനങ്ങൾ",
    "myOrders": "എന്റെ ഓർഡറുകൾ",
    "secureHotelDining": "സുരക്ഷിത ഹോട്ടൽ ഡൈനിംഗ്",
    "roomLinked": "നിങ്ങളുടെ ഓർഡർ റൂം {room}യും സജീവ താമസവും മാത്രം ബന്ധിപ്പിച്ചിരിക്കുന്നു.",
    "poweredSecurelyBy": "സുരക്ഷിതമായി നൽകുന്നത്",
    "backToGuestGuide": "ഗസ്റ്റ് ഗൈഡിലേക്ക് മടങ്ങുക",
    "room": "റൂം",
    "stayActive": "താമസം സജീവം",
    "stayqrDining": "StayQR ഡൈനിംഗ്",
    "diningDelivered": "ഹോട്ടൽ ഭക്ഷണം നേരിട്ട് നിങ്ങളുടെ റൂമിലേക്ക്.",
    "approx": "ഏകദേശം",
    "min": "മിനിറ്റ്",
    "secureOrdering": "സുരക്ഷിത ഓർഡറിംഗ്",
    "liveKitchenTracking": "ലൈവ് കിച്ചൺ ട്രാക്കിംഗ്",
    "language": "ഭാഷ",
    "all": "എല്ലാം",
    "featured": "പ്രത്യേകം",
    "curatedForStay": "നിങ്ങളുടെ താമസത്തിനായി തെരഞ്ഞെടുത്തത്",
    "inRoomDiningMenu": "ഇൻ-റൂം ഡൈനിംഗ് മെനു",
    "featuredForYou": "നിങ്ങൾക്കായി പ്രത്യേകം",
    "exploreMenu": "മെനു കാണുക",
    "available": "ലഭ്യം",
    "noItemsTitle": "ഈ വിഭാഗത്തിൽ ഇനങ്ങൾ ലഭ്യമല്ല.",
    "noItemsBody": "മറ്റൊരു വിഭാഗം തിരഞ്ഞെടുക്കുക അല്ലെങ്കിൽ ഹോട്ടലിനെ ബന്ധപ്പെടുക.",
    "customisable": "മാറ്റാവുന്നത്",
    "hotelMenu": "ഹോട്ടൽ മെനു",
    "preparedFresh": "ഹോട്ടൽ അടുക്കളയിൽ പുതുതായി തയ്യാറാക്കിയത്.",
    "tax": "നികുതി",
    "included": "ഉൾപ്പെടുന്നു",
    "extra": "അധികം",
    "customiseAdd": "മാറ്റി ചേർക്കുക",
    "addToCart": "കാർട്ടിൽ ചേർക്കുക",
    "behindEveryOrder": "ഓരോ ഓർഡറിനും പിന്നിൽ",
    "kitchenCares": "കരുതലുള്ള അടുക്കള.",
    "kitchenStoryBody": "പുതിയ തയ്യാറാക്കൽ, ശുചിത്വ കൈകാര്യം, ലൈവ് അപ്ഡേറ്റുകൾ.",
    "watchKitchenStory": "കിച്ചൺ കഥ കാണുക",
    "freshlyPrepared": "പുതുതായി തയ്യാറാക്കി",
    "madeToOrder": "ഓർഡർ അനുസരിച്ച് തയ്യാറാക്കുന്നു.",
    "hygienicSecure": "ശുചിത്വവും സുരക്ഷയും",
    "activeRoomSecure": "ഓർഡർ സജീവ റൂമുമായി ബന്ധിപ്പിച്ചു.",
    "liveTracking": "ലൈവ് ട്രാക്കിംഗ്",
    "liveTrackingBody": "ഓരോ കിച്ചൺ നിലയും ലൈവായി കാണുക.",
    "yourActiveOrder": "നിങ്ങളുടെ സജീവ ഓർഡർ",
    "yourCart": "നിങ്ങളുടെ കാർട്ട്",
    "cartEmpty": "നിങ്ങളുടെ കാർട്ട് ശൂന്യമാണ്",
    "cartEmptyBody": "റൂം ഡൈനിംഗിനായി ഇനങ്ങൾ തിരഞ്ഞെടുക്കുക.",
    "itemSubtotal": "ഇനം ഉപമൊത്തം",
    "addOns": "ആഡ്-ഓൺസ്",
    "taxes": "നികുതികൾ",
    "total": "മൊത്തം",
    "secureOrderFromRoom": "റൂം {room}ൽ നിന്ന് സുരക്ഷിത ഓർഡർ.",
    "placeSecureOrder": "സുരക്ഷിത ഓർഡർ ചെയ്യുക",
    "sendingOrder": "ഓർഡർ അയക്കുന്നു…",
    "continueShopping": "കൂടുതൽ കാണുക",
    "yourOrders": "നിങ്ങളുടെ ഓർഡറുകൾ",
    "orderSingular": "ഓർഡർ",
    "orderPlural": "ഓർഡറുകൾ",
    "noOrders": "ഈ താമസത്തിൽ ഭക്ഷണ ഓർഡർ ഇല്ല.",
    "estimatedDelivery": "കണക്കാക്കിയ ഡെലിവറി",
    "cancelOrder": "ഓർഡർ റദ്ദാക്കുക",
    "thisOrderCancelled": "ഈ ഓർഡർ റദ്ദാക്കി.",
    "kitchenMessages": "കിച്ചൺ സന്ദേശങ്ങൾ",
    "latestUpdates": "പുതിയ അപ്ഡേറ്റുകൾ",
    "secureGuestExperience": "സുരക്ഷിത ഹോട്ടൽ അനുഭവം",
    "customiseOrder": "നിങ്ങളുടെ ഓർഡർ മാറ്റുക",
    "required": "ആവശ്യമാണ്",
    "optional": "ഐച്ഛികം",
    "choose": "തിരഞ്ഞെടുക്കുക",
    "optionSingular": "ഓപ്ഷൻ",
    "optionPlural": "ഓപ്ഷനുകൾ",
    "includedPrice": "ഉൾപ്പെടുന്നു",
    "dueNow": "ഇപ്പോൾ",
    "minuteSingular": "മിനിറ്റ്",
    "minutePlural": "മിനിറ്റുകൾ",
    "statusPending": "കാത്തിരിക്കുന്നു",
    "statusAccepted": "സ്വീകരിച്ചു",
    "statusPreparing": "തയ്യാറാകുന്നു",
    "statusReady": "തയ്യാർ",
    "statusOutForDelivery": "വഴിയിൽ",
    "statusDelivered": "എത്തിച്ചു",
    "statusCancelled": "റദ്ദാക്കി",
    "offerCtaDefault": "ഓഫർ കാണുക",
    "offerBadgeDefault": "പരിമിത ഓഫർ",
    "offerTitleDefault": "നിങ്ങളുടെ താമസം കൂടുതൽ പ്രത്യേകമാക്കൂ",
    "offerDescriptionDefault": "ഇന്നത്തെ അതിഥി ആനുകൂല്യത്തെക്കുറിച്ച് റിസപ്ഷനിൽ ചോദിക്കുക.",
    "saveOffer": "ഓഫർ സേവ് ചെയ്യുക",
    "publishOffer": "സേവ് ചെയ്ത് പ്രസിദ്ധീകരിക്കുക"
  },
  "pa": {
    "loading": "ਤੁਹਾਡਾ StayQR ਡਾਇਨਿੰਗ ਅਨੁਭਵ ਤਿਆਰ ਹੋ ਰਿਹਾ ਹੈ…",
    "accessUnavailable": "ਮਹਿਮਾਨ ਪਹੁੰਚ ਉਪਲਬਧ ਨਹੀਂ",
    "accessUnavailableBody": "ਇਹ ਭੋਜਨ ਆਰਡਰ ਲਿੰਕ ਅਵੈਧ ਜਾਂ ਮਿਆਦ ਪੁੱਗਿਆ ਹੈ।",
    "menuLoadFailed": "ਮੇਨੂ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕਿਆ।",
    "addedToCart": "ਕਾਰਟ ਵਿੱਚ ਜੋੜਿਆ ਗਿਆ।",
    "chooseOptions": "{group} ਲਈ {range} ਚੋਣਾਂ ਚੁਣੋ।",
    "orderAlreadyReceived": "ਇਹ ਆਰਡਰ ਪਹਿਲਾਂ ਹੀ ਮਿਲ ਚੁੱਕਾ ਹੈ।",
    "orderSent": "ਆਰਡਰ ਰਸੋਈ ਨੂੰ ਭੇਜਿਆ ਗਿਆ।",
    "cancelConfirm": "ਇਹ ਭੋਜਨ ਆਰਡਰ ਰੱਦ ਕਰਨਾ ਹੈ?",
    "orderCancelled": "ਆਰਡਰ ਰੱਦ ਹੋ ਗਿਆ।",
    "unableCancel": "ਆਰਡਰ ਰੱਦ ਨਹੀਂ ਹੋ ਸਕਿਆ।",
    "dining": "ਡਾਇਨਿੰਗ",
    "guestGuide": "ਗੈਸਟ ਗਾਈਡ",
    "inRoomServices": "ਕਮਰੇ ਦੀਆਂ ਸੇਵਾਵਾਂ",
    "myOrders": "ਮੇਰੇ ਆਰਡਰ",
    "secureHotelDining": "ਸੁਰੱਖਿਅਤ ਹੋਟਲ ਡਾਇਨਿੰਗ",
    "roomLinked": "ਤੁਹਾਡਾ ਆਰਡਰ ਸਿਰਫ ਕਮਰਾ {room} ਅਤੇ ਸਰਗਰਮ ਰਹਿਣ ਨਾਲ ਜੁੜਿਆ ਹੈ।",
    "poweredSecurelyBy": "ਸੁਰੱਖਿਅਤ ਤਰੀਕੇ ਨਾਲ",
    "backToGuestGuide": "ਗੈਸਟ ਗਾਈਡ ਤੇ ਵਾਪਸ",
    "room": "ਕਮਰਾ",
    "stayActive": "ਰਹਿਣ ਸਰਗਰਮ",
    "stayqrDining": "StayQR ਡਾਇਨਿੰਗ",
    "diningDelivered": "ਹੋਟਲ ਭੋਜਨ ਸਿੱਧਾ ਤੁਹਾਡੇ ਕਮਰੇ ਵਿੱਚ।",
    "approx": "ਲਗਭਗ",
    "min": "ਮਿੰਟ",
    "secureOrdering": "ਸੁਰੱਖਿਅਤ ਆਰਡਰਿੰਗ",
    "liveKitchenTracking": "ਲਾਈਵ ਕਿਚਨ ਟ੍ਰੈਕਿੰਗ",
    "language": "ਭਾਸ਼ਾ",
    "all": "ਸਭ",
    "featured": "ਖਾਸ",
    "curatedForStay": "ਤੁਹਾਡੇ ਰਹਿਣ ਲਈ ਚੁਣਿਆ",
    "inRoomDiningMenu": "ਇਨ-ਰੂਮ ਡਾਇਨਿੰਗ ਮੇਨੂ",
    "featuredForYou": "ਤੁਹਾਡੇ ਲਈ ਖਾਸ",
    "exploreMenu": "ਮੇਨੂ ਵੇਖੋ",
    "available": "ਉਪਲਬਧ",
    "noItemsTitle": "ਇਸ ਸ਼੍ਰੇਣੀ ਵਿੱਚ ਕੋਈ ਆਈਟਮ ਨਹੀਂ।",
    "noItemsBody": "ਹੋਰ ਸ਼੍ਰੇਣੀ ਚੁਣੋ ਜਾਂ ਹੋਟਲ ਨਾਲ ਸੰਪਰਕ ਕਰੋ।",
    "customisable": "ਬਦਲਿਆ ਜਾ ਸਕਦਾ",
    "hotelMenu": "ਹੋਟਲ ਮੇਨੂ",
    "preparedFresh": "ਹੋਟਲ ਰਸੋਈ ਵਿੱਚ ਤਾਜ਼ਾ ਤਿਆਰ।",
    "tax": "ਟੈਕਸ",
    "included": "ਸ਼ਾਮਲ",
    "extra": "ਵਾਧੂ",
    "customiseAdd": "ਬਦਲੋ ਅਤੇ ਜੋੜੋ",
    "addToCart": "ਕਾਰਟ ਵਿੱਚ ਜੋੜੋ",
    "behindEveryOrder": "ਹਰ ਆਰਡਰ ਦੇ ਪਿੱਛੇ",
    "kitchenCares": "ਪਰਵਾਹ ਕਰਨ ਵਾਲੀ ਰਸੋਈ।",
    "kitchenStoryBody": "ਤਾਜ਼ਾ ਤਿਆਰੀ, ਸਫਾਈ ਅਤੇ ਲਾਈਵ ਅਪਡੇਟ।",
    "watchKitchenStory": "ਕਿਚਨ ਕਹਾਣੀ ਵੇਖੋ",
    "freshlyPrepared": "ਤਾਜ਼ਾ ਤਿਆਰ",
    "madeToOrder": "ਆਰਡਰ ਅਨੁਸਾਰ ਤਿਆਰ।",
    "hygienicSecure": "ਸਾਫ਼ ਅਤੇ ਸੁਰੱਖਿਅਤ",
    "activeRoomSecure": "ਆਰਡਰ ਸਰਗਰਮ ਕਮਰੇ ਨਾਲ ਜੁੜਿਆ ਹੈ।",
    "liveTracking": "ਲਾਈਵ ਟ੍ਰੈਕਿੰਗ",
    "liveTrackingBody": "ਹਰ ਕਿਚਨ ਸਥਿਤੀ ਲਾਈਵ ਵੇਖੋ।",
    "yourActiveOrder": "ਤੁਹਾਡਾ ਸਰਗਰਮ ਆਰਡਰ",
    "yourCart": "ਤੁਹਾਡਾ ਕਾਰਟ",
    "cartEmpty": "ਤੁਹਾਡਾ ਕਾਰਟ ਖਾਲੀ ਹੈ",
    "cartEmptyBody": "ਕਮਰੇ ਦੇ ਭੋਜਨ ਲਈ ਆਈਟਮ ਚੁਣੋ।",
    "itemSubtotal": "ਆਈਟਮ ਉਪ-ਕੁੱਲ",
    "addOns": "ਐਡ-ਆਨ",
    "taxes": "ਟੈਕਸ",
    "total": "ਕੁੱਲ",
    "secureOrderFromRoom": "ਕਮਰਾ {room} ਤੋਂ ਸੁਰੱਖਿਅਤ ਆਰਡਰ।",
    "placeSecureOrder": "ਸੁਰੱਖਿਅਤ ਆਰਡਰ ਕਰੋ",
    "sendingOrder": "ਆਰਡਰ ਭੇਜਿਆ ਜਾ ਰਿਹਾ ਹੈ…",
    "continueShopping": "ਹੋਰ ਵੇਖੋ",
    "yourOrders": "ਤੁਹਾਡੇ ਆਰਡਰ",
    "orderSingular": "ਆਰਡਰ",
    "orderPlural": "ਆਰਡਰ",
    "noOrders": "ਇਸ ਰਹਿਣ ਦੌਰਾਨ ਕੋਈ ਭੋਜਨ ਆਰਡਰ ਨਹੀਂ।",
    "estimatedDelivery": "ਅੰਦਾਜ਼ਨ ਡਿਲਿਵਰੀ",
    "cancelOrder": "ਆਰਡਰ ਰੱਦ ਕਰੋ",
    "thisOrderCancelled": "ਇਹ ਆਰਡਰ ਰੱਦ ਹੋ ਗਿਆ।",
    "kitchenMessages": "ਕਿਚਨ ਸੁਨੇਹੇ",
    "latestUpdates": "ਨਵੇਂ ਅਪਡੇਟ",
    "secureGuestExperience": "ਸੁਰੱਖਿਅਤ ਹੋਟਲ ਅਨੁਭਵ",
    "customiseOrder": "ਆਪਣਾ ਆਰਡਰ ਬਦਲੋ",
    "required": "ਲਾਜ਼ਮੀ",
    "optional": "ਵਿਕਲਪਿਕ",
    "choose": "ਚੁਣੋ",
    "optionSingular": "ਚੋਣ",
    "optionPlural": "ਚੋਣਾਂ",
    "includedPrice": "ਸ਼ਾਮਲ",
    "dueNow": "ਹੁਣ",
    "minuteSingular": "ਮਿੰਟ",
    "minutePlural": "ਮਿੰਟ",
    "statusPending": "ਬਕਾਇਆ",
    "statusAccepted": "ਸਵੀਕਾਰਿਆ",
    "statusPreparing": "ਤਿਆਰ ਹੋ ਰਿਹਾ",
    "statusReady": "ਤਿਆਰ",
    "statusOutForDelivery": "ਰਸਤੇ ਵਿੱਚ",
    "statusDelivered": "ਪਹੁੰਚਾਇਆ",
    "statusCancelled": "ਰੱਦ",
    "offerCtaDefault": "ਆਫਰ ਵੇਖੋ",
    "offerBadgeDefault": "ਸੀਮਿਤ ਆਫ਼ਰ",
    "offerTitleDefault": "ਆਪਣੇ ਠਹਿਰਾਅ ਨੂੰ ਹੋਰ ਖਾਸ ਬਣਾਓ",
    "offerDescriptionDefault": "ਅੱਜ ਦੇ ਮਹਿਮਾਨ ਲਾਭ ਬਾਰੇ ਰਿਸੈਪਸ਼ਨ ਤੋਂ ਪੁੱਛੋ।",
    "saveOffer": "ਆਫਰ ਸੰਭਾਲੋ",
    "publishOffer": "ਸੰਭਾਲੋ ਅਤੇ ਪ੍ਰਕਾਸ਼ਿਤ ਕਰੋ"
  },
  "or": {
    "loading": "ଆପଣଙ୍କ StayQR ଡାଇନିଂ ଅନୁଭବ ପ୍ରସ୍ତୁତ ହେଉଛି…",
    "accessUnavailable": "ଅତିଥି ପ୍ରବେଶ ଉପଲବ୍ଧ ନାହିଁ",
    "accessUnavailableBody": "ଏହି ଖାଦ୍ୟ ଅର୍ଡର ଲିଙ୍କ ଅବୈଧ କିମ୍ବା ସମୟସୀମା ଶେଷ।",
    "menuLoadFailed": "ମେନୁ ଲୋଡ୍ ହୋଇପାରିଲା ନାହିଁ।",
    "addedToCart": "କାର୍ଟରେ ଯୋଡାଗଲା।",
    "chooseOptions": "{group} ପାଇଁ {range} ବିକଳ୍ପ ବାଛନ୍ତୁ।",
    "orderAlreadyReceived": "ଏହି ଅର୍ଡର ପୂର୍ବରୁ ମିଳିଛି।",
    "orderSent": "ଅର୍ଡର ରୋଷେଇଘରକୁ ପଠାଗଲା।",
    "cancelConfirm": "ଏହି ଖାଦ୍ୟ ଅର୍ଡର ବାତିଲ କରିବେ?",
    "orderCancelled": "ଅର୍ଡର ବାତିଲ ହେଲା।",
    "unableCancel": "ଅର୍ଡର ବାତିଲ ହୋଇପାରିଲା ନାହିଁ।",
    "dining": "ଡାଇନିଂ",
    "guestGuide": "ଅତିଥି ଗାଇଡ୍",
    "inRoomServices": "କୋଠରୀ ସେବା",
    "myOrders": "ମୋ ଅର୍ଡର",
    "secureHotelDining": "ସୁରକ୍ଷିତ ହୋଟେଲ ଡାଇନିଂ",
    "roomLinked": "ଆପଣଙ୍କ ଅର୍ଡର କେବଳ କୋଠରୀ {room} ଏବଂ ସକ୍ରିୟ ରହଣି ସହ ଯୋଡା।",
    "poweredSecurelyBy": "ସୁରକ୍ଷିତ ଭାବେ ପରିଚାଳିତ",
    "backToGuestGuide": "ଅତିଥି ଗାଇଡ୍‌କୁ ଫେରନ୍ତୁ",
    "room": "କୋଠରୀ",
    "stayActive": "ରହଣି ସକ୍ରିୟ",
    "stayqrDining": "StayQR ଡାଇନିଂ",
    "diningDelivered": "ହୋଟେଲ ଭୋଜନ ସିଧା ଆପଣଙ୍କ କୋଠରୀକୁ।",
    "approx": "ପ୍ରାୟ",
    "min": "ମିନିଟ୍",
    "secureOrdering": "ସୁରକ୍ଷିତ ଅର୍ଡରିଂ",
    "liveKitchenTracking": "ଲାଇଭ୍ କିଚେନ୍ ଟ୍ରାକିଂ",
    "language": "ଭାଷା",
    "all": "ସବୁ",
    "featured": "ବିଶେଷ",
    "curatedForStay": "ଆପଣଙ୍କ ରହଣି ପାଇଁ ବାଛିତ",
    "inRoomDiningMenu": "କୋଠରୀ ଡାଇନିଂ ମେନୁ",
    "featuredForYou": "ଆପଣଙ୍କ ପାଇଁ ବିଶେଷ",
    "exploreMenu": "ମେନୁ ଦେଖନ୍ତୁ",
    "available": "ଉପଲବ୍ଧ",
    "noItemsTitle": "ଏହି ବିଭାଗରେ ଖାଦ୍ୟ ନାହିଁ।",
    "noItemsBody": "ଅନ୍ୟ ବିଭାଗ ବାଛନ୍ତୁ କିମ୍ବା ହୋଟେଲକୁ ଯୋଗାଯୋଗ କରନ୍ତୁ।",
    "customisable": "ପରିବର୍ତ୍ତନଯୋଗ୍ୟ",
    "hotelMenu": "ହୋଟେଲ ମେନୁ",
    "preparedFresh": "ହୋଟେଲ ରୋଷେଇଘରରେ ତାଜା ପ୍ରସ୍ତୁତ।",
    "tax": "କର",
    "included": "ସମ୍ମିଳିତ",
    "extra": "ଅତିରିକ୍ତ",
    "customiseAdd": "ପରିବର୍ତ୍ତନ କରି ଯୋଡନ୍ତୁ",
    "addToCart": "କାର୍ଟରେ ଯୋଡନ୍ତୁ",
    "behindEveryOrder": "ପ୍ରତ୍ୟେକ ଅର୍ଡର ପଛରେ",
    "kitchenCares": "ଯତ୍ନଶୀଳ ରୋଷେଇଘର।",
    "kitchenStoryBody": "ତାଜା ପ୍ରସ୍ତୁତି, ସ୍ୱଚ୍ଛତା ଏବଂ ଲାଇଭ୍ ଅପଡେଟ୍।",
    "watchKitchenStory": "କିଚେନ୍ କଥା ଦେଖନ୍ତୁ",
    "freshlyPrepared": "ତାଜା ପ୍ରସ୍ତୁତ",
    "madeToOrder": "ଅର୍ଡର ଅନୁଯାୟୀ ପ୍ରସ୍ତୁତ।",
    "hygienicSecure": "ସ୍ୱଚ୍ଛ ଏବଂ ସୁରକ୍ଷିତ",
    "activeRoomSecure": "ଅର୍ଡର ସକ୍ରିୟ କୋଠରୀ ସହ ଯୋଡା।",
    "liveTracking": "ଲାଇଭ୍ ଟ୍ରାକିଂ",
    "liveTrackingBody": "ପ୍ରତ୍ୟେକ କିଚେନ୍ ସ୍ଥିତି ଲାଇଭ୍ ଦେଖନ୍ତୁ।",
    "yourActiveOrder": "ଆପଣଙ୍କ ସକ୍ରିୟ ଅର୍ଡର",
    "yourCart": "ଆପଣଙ୍କ କାର୍ଟ",
    "cartEmpty": "ଆପଣଙ୍କ କାର୍ଟ ଖାଲି",
    "cartEmptyBody": "କୋଠରୀ ଭୋଜନ ପାଇଁ ଆଇଟମ୍ ବାଛନ୍ତୁ।",
    "itemSubtotal": "ଆଇଟମ୍ ଉପମୋଟ",
    "addOns": "ଆଡ୍-ଅନ୍",
    "taxes": "କର",
    "total": "ମୋଟ",
    "secureOrderFromRoom": "କୋଠରୀ {room}ରୁ ସୁରକ୍ଷିତ ଅର୍ଡର।",
    "placeSecureOrder": "ସୁରକ୍ଷିତ ଅର୍ଡର କରନ୍ତୁ",
    "sendingOrder": "ଅର୍ଡର ପଠାଯାଉଛି…",
    "continueShopping": "ଆଉ ଦେଖନ୍ତୁ",
    "yourOrders": "ଆପଣଙ୍କ ଅର୍ଡର",
    "orderSingular": "ଅର୍ଡର",
    "orderPlural": "ଅର୍ଡର",
    "noOrders": "ଏହି ରହଣିରେ ଖାଦ୍ୟ ଅର୍ଡର ନାହିଁ।",
    "estimatedDelivery": "ଆନୁମାନିକ ଡେଲିଭରି",
    "cancelOrder": "ଅର୍ଡର ବାତିଲ",
    "thisOrderCancelled": "ଏହି ଅର୍ଡର ବାତିଲ ହୋଇଛି।",
    "kitchenMessages": "କିଚେନ୍ ସନ୍ଦେଶ",
    "latestUpdates": "ନୂତନ ଅପଡେଟ୍",
    "secureGuestExperience": "ସୁରକ୍ଷିତ ହୋଟେଲ ଅନୁଭବ",
    "customiseOrder": "ଆପଣଙ୍କ ଅର୍ଡର ବଦଳାନ୍ତୁ",
    "required": "ଆବଶ୍ୟକ",
    "optional": "ଇଚ୍ଛାଧୀନ",
    "choose": "ବାଛନ୍ତୁ",
    "optionSingular": "ବିକଳ୍ପ",
    "optionPlural": "ବିକଳ୍ପ",
    "includedPrice": "ସମ୍ମିଳିତ",
    "dueNow": "ଏବେ",
    "minuteSingular": "ମିନିଟ୍",
    "minutePlural": "ମିନିଟ୍",
    "statusPending": "ଅପେକ୍ଷାରତ",
    "statusAccepted": "ଗ୍ରହଣ କରାଗଲା",
    "statusPreparing": "ପ୍ରସ୍ତୁତ ହେଉଛି",
    "statusReady": "ପ୍ରସ୍ତୁତ",
    "statusOutForDelivery": "ରାସ୍ତାରେ",
    "statusDelivered": "ପହଞ୍ଚିଲା",
    "statusCancelled": "ବାତିଲ",
    "offerCtaDefault": "ଅଫର ଦେଖନ୍ତୁ",
    "offerBadgeDefault": "ସୀମିତ ଅଫର",
    "offerTitleDefault": "ଆପଣଙ୍କ ରହଣିକୁ ଆହୁରି ବିଶେଷ କରନ୍ତୁ",
    "offerDescriptionDefault": "ଆଜିର ଅତିଥି ସୁବିଧା ବିଷୟରେ ରିସେପ୍ସନ୍‌ରେ ପଚାରନ୍ତୁ।",
    "saveOffer": "ଅଫର ସଞ୍ଚୟ",
    "publishOffer": "ସଞ୍ଚୟ ଏବଂ ପ୍ରକାଶ"
  },
  "as": {
    "loading": "আপোনাৰ StayQR ডাইনিং অভিজ্ঞতা প্ৰস্তুত হৈ আছে…",
    "accessUnavailable": "অতিথি প্ৰৱেশ উপলব্ধ নহয়",
    "accessUnavailableBody": "এই খাদ্য অৰ্ডাৰ লিংক অবৈধ বা মেয়াদ শেষ।",
    "menuLoadFailed": "মেনু লোড কৰিব নোৱাৰিলে।",
    "addedToCart": "কাৰ্টত যোগ কৰা হ’ল।",
    "chooseOptions": "{group}ৰ বাবে {range} বিকল্প বাছক।",
    "orderAlreadyReceived": "এই অৰ্ডাৰ ইতিমধ্যে পোৱা গৈছে।",
    "orderSent": "অৰ্ডাৰ পাকঘৰলৈ পঠোৱা হ’ল।",
    "cancelConfirm": "এই খাদ্য অৰ্ডাৰ বাতিল কৰিবনে?",
    "orderCancelled": "অৰ্ডাৰ বাতিল হ’ল।",
    "unableCancel": "অৰ্ডাৰ বাতিল কৰিব নোৱাৰিলে।",
    "dining": "ডাইনিং",
    "guestGuide": "অতিথি গাইড",
    "inRoomServices": "কোঠাৰ সেৱা",
    "myOrders": "মোৰ অৰ্ডাৰ",
    "secureHotelDining": "সুৰক্ষিত হোটেল ডাইনিং",
    "roomLinked": "আপোনাৰ অৰ্ডাৰ কেৱল কোঠা {room} আৰু সক্ৰিয় থাকনিৰ সৈতে সংযুক্ত।",
    "poweredSecurelyBy": "সুৰক্ষিতভাৱে পৰিচালিত",
    "backToGuestGuide": "অতিথি গাইডলৈ উভতি যাওক",
    "room": "কোঠা",
    "stayActive": "থাকনি সক্ৰিয়",
    "stayqrDining": "StayQR ডাইনিং",
    "diningDelivered": "হোটেলৰ খাদ্য পোনে পোনে আপোনাৰ কোঠালৈ।",
    "approx": "প্ৰায়",
    "min": "মিনিট",
    "secureOrdering": "সুৰক্ষিত অৰ্ডাৰিং",
    "liveKitchenTracking": "লাইভ পাকঘৰ ট্ৰেকিং",
    "language": "ভাষা",
    "all": "সকলো",
    "featured": "বিশেষ",
    "curatedForStay": "আপোনাৰ থাকনিৰ বাবে বাছনি",
    "inRoomDiningMenu": "কোঠাৰ ডাইনিং মেনু",
    "featuredForYou": "আপোনাৰ বাবে বিশেষ",
    "exploreMenu": "মেনু চাওক",
    "available": "উপলব্ধ",
    "noItemsTitle": "এই বিভাগত কোনো আইটেম নাই।",
    "noItemsBody": "অন্য বিভাগ বাছক বা হোটেলৰ সৈতে যোগাযোগ কৰক।",
    "customisable": "সালসলনি কৰিব পৰা",
    "hotelMenu": "হোটেল মেনু",
    "preparedFresh": "হোটেল পাকঘৰত সতেজভাৱে তৈয়াৰ।",
    "tax": "কৰ",
    "included": "অন্তৰ্ভুক্ত",
    "extra": "অতিৰিক্ত",
    "customiseAdd": "সালসলনি কৰি যোগ কৰক",
    "addToCart": "কাৰ্টত যোগ কৰক",
    "behindEveryOrder": "প্ৰতিটো অৰ্ডাৰৰ আঁৰত",
    "kitchenCares": "যত্নশীল পাকঘৰ।",
    "kitchenStoryBody": "সতেজ প্ৰস্তুতি, পৰিষ্কাৰ ব্যৱস্থা আৰু লাইভ আপডেট।",
    "watchKitchenStory": "পাকঘৰৰ কাহিনী চাওক",
    "freshlyPrepared": "সতেজ প্ৰস্তুত",
    "madeToOrder": "অৰ্ডাৰ অনুসৰি তৈয়াৰ।",
    "hygienicSecure": "পৰিষ্কাৰ আৰু সুৰক্ষিত",
    "activeRoomSecure": "অৰ্ডাৰ সক্ৰিয় কোঠাৰ সৈতে সংযুক্ত।",
    "liveTracking": "লাইভ ট্ৰেকিং",
    "liveTrackingBody": "প্ৰতিটো পাকঘৰ অৱস্থা লাইভ চাওক।",
    "yourActiveOrder": "আপোনাৰ সক্ৰিয় অৰ্ডাৰ",
    "yourCart": "আপোনাৰ কাৰ্ট",
    "cartEmpty": "আপোনাৰ কাৰ্ট খালী",
    "cartEmptyBody": "কোঠাৰ ডাইনিংৰ বাবে আইটেম বাছক।",
    "itemSubtotal": "আইটেম উপমুঠ",
    "addOns": "এড-অন",
    "taxes": "কৰ",
    "total": "মুঠ",
    "secureOrderFromRoom": "কোঠা {room}ৰ পৰা সুৰক্ষিত অৰ্ডাৰ।",
    "placeSecureOrder": "সুৰক্ষিত অৰ্ডাৰ কৰক",
    "sendingOrder": "অৰ্ডাৰ পঠোৱা হৈছে…",
    "continueShopping": "আৰু চাওক",
    "yourOrders": "আপোনাৰ অৰ্ডাৰ",
    "orderSingular": "অৰ্ডাৰ",
    "orderPlural": "অৰ্ডাৰ",
    "noOrders": "এই থাকনিত খাদ্য অৰ্ডাৰ নাই।",
    "estimatedDelivery": "আনুমানিক ডেলিভাৰী",
    "cancelOrder": "অৰ্ডাৰ বাতিল",
    "thisOrderCancelled": "এই অৰ্ডাৰ বাতিল কৰা হৈছে।",
    "kitchenMessages": "পাকঘৰৰ বাৰ্তা",
    "latestUpdates": "শেহতীয়া আপডেট",
    "secureGuestExperience": "সুৰক্ষিত হোটেল অভিজ্ঞতা",
    "customiseOrder": "আপোনাৰ অৰ্ডাৰ সালসলনি কৰক",
    "required": "আৱশ্যক",
    "optional": "ঐচ্ছিক",
    "choose": "বাছক",
    "optionSingular": "বিকল্প",
    "optionPlural": "বিকল্প",
    "includedPrice": "অন্তৰ্ভুক্ত",
    "dueNow": "এতিয়া",
    "minuteSingular": "মিনিট",
    "minutePlural": "মিনিট",
    "statusPending": "অপেক্ষমাণ",
    "statusAccepted": "গ্ৰহণ কৰা",
    "statusPreparing": "প্ৰস্তুত হৈছে",
    "statusReady": "প্ৰস্তুত",
    "statusOutForDelivery": "পথত",
    "statusDelivered": "পহুওৱা হৈছে",
    "statusCancelled": "বাতিল",
    "offerCtaDefault": "অফাৰ চাওক",
    "offerBadgeDefault": "সীমিত অফাৰ",
    "offerTitleDefault": "আপোনাৰ থকাটো অধিক বিশেষ কৰক",
    "offerDescriptionDefault": "আজিৰ অতিথি সুবিধাৰ বিষয়ে ৰিচেপচনত সোধক।",
    "saveOffer": "অফাৰ সংৰক্ষণ",
    "publishOffer": "সংৰক্ষণ আৰু প্ৰকাশ"
  }
}

const CATEGORY_TRANSLATIONS = {
  "en": {
    "breakfast": "Breakfast",
    "lunch": "Lunch",
    "dinner": "Dinner",
    "beverages": "Beverages",
    "meal": "Meal",
    "all": "All"
  },
  "hi": {
    "breakfast": "नाश्ता",
    "lunch": "दोपहर का भोजन",
    "dinner": "रात का भोजन",
    "beverages": "पेय",
    "meal": "मुख्य भोजन",
    "all": "सभी"
  },
  "mr": {
    "breakfast": "नाश्ता",
    "lunch": "दुपारचे जेवण",
    "dinner": "रात्रीचे जेवण",
    "beverages": "पेय",
    "meal": "मुख्य जेवण",
    "all": "सर्व"
  },
  "ta": {
    "breakfast": "காலை உணவு",
    "lunch": "மதிய உணவு",
    "dinner": "இரவு உணவு",
    "beverages": "பானங்கள்",
    "meal": "முக்கிய உணவு",
    "all": "அனைத்தும்"
  },
  "te": {
    "breakfast": "అల్పాహారం",
    "lunch": "మధ్యాహ్న భోజనం",
    "dinner": "రాత్రి భోజనం",
    "beverages": "పానీయాలు",
    "meal": "ప్రధాన భోజనం",
    "all": "అన్నీ"
  },
  "bn": {
    "breakfast": "সকালের নাশতা",
    "lunch": "দুপুরের খাবার",
    "dinner": "রাতের খাবার",
    "beverages": "পানীয়",
    "meal": "মূল খাবার",
    "all": "সব"
  },
  "gu": {
    "breakfast": "નાસ્તો",
    "lunch": "બપોરનું ભોજન",
    "dinner": "રાત્રિભોજન",
    "beverages": "પીણાં",
    "meal": "મુખ્ય ભોજન",
    "all": "બધું"
  },
  "kn": {
    "breakfast": "ಬೆಳಗಿನ ಉಪಹಾರ",
    "lunch": "ಮಧ್ಯಾಹ್ನದ ಊಟ",
    "dinner": "ರಾತ್ರಿ ಊಟ",
    "beverages": "ಪಾನೀಯಗಳು",
    "meal": "ಮುಖ್ಯ ಊಟ",
    "all": "ಎಲ್ಲ"
  },
  "ml": {
    "breakfast": "പ്രഭാതഭക്ഷണം",
    "lunch": "ഉച്ചഭക്ഷണം",
    "dinner": "അത്താഴം",
    "beverages": "പാനീയങ്ങൾ",
    "meal": "പ്രധാന ഭക്ഷണം",
    "all": "എല്ലാം"
  },
  "pa": {
    "breakfast": "ਨਾਸ਼ਤਾ",
    "lunch": "ਦੁਪਹਿਰ ਦਾ ਖਾਣਾ",
    "dinner": "ਰਾਤ ਦਾ ਖਾਣਾ",
    "beverages": "ਪੀਣ ਵਾਲੀਆਂ ਚੀਜ਼ਾਂ",
    "meal": "ਮੁੱਖ ਭੋਜਨ",
    "all": "ਸਭ"
  },
  "or": {
    "breakfast": "ଜଳଖିଆ",
    "lunch": "ମଧ୍ୟାହ୍ନ ଭୋଜନ",
    "dinner": "ରାତି ଭୋଜନ",
    "beverages": "ପାନୀୟ",
    "meal": "ମୁଖ୍ୟ ଭୋଜନ",
    "all": "ସବୁ"
  },
  "as": {
    "breakfast": "পুৱাৰ আহাৰ",
    "lunch": "দুপৰীয়াৰ আহাৰ",
    "dinner": "ৰাতিৰ আহাৰ",
    "beverages": "পানীয়",
    "meal": "মূল আহাৰ",
    "all": "সকলো"
  }
}

const ITEM_TRANSLATIONS = {
  "biryani": {
    "en": [
      "Biryani",
      "Fragrant long-grain rice layered with rich spices and slow-cooked for full flavour."
    ],
    "hi": [
      "बिरयानी",
      "सुगंधित लंबे चावल, मसालों और धीमी आंच पर तैयार भरपूर स्वाद वाली बिरयानी।"
    ],
    "mr": [
      "बिर्याणी",
      "सुगंधी लांब तांदूळ, मसाले आणि मंद आचेवर तयार केलेली चवदार बिर्याणी."
    ],
    "ta": [
      "பிரியாணி",
      "மணமுள்ள நீள அரிசி மற்றும் மசாலாவுடன் மெதுவாக சமைத்த சுவையான பிரியாணி."
    ],
    "te": [
      "బిర్యానీ",
      "సువాసన గల పొడవాటి బియ్యం, మసాలాలతో నెమ్మదిగా వండిన బిర్యానీ."
    ],
    "bn": [
      "বিরিয়ানি",
      "সুগন্ধি লম্বা চাল ও মসলায় ধীরে রান্না করা স্বাদযুক্ত বিরিয়ানি।"
    ],
    "gu": [
      "બિરયાની",
      "સુગંધિત લાંબા ચોખા અને મસાલા સાથે ધીમે રાંધેલી સ્વાદિષ્ટ બિરયાની."
    ],
    "kn": [
      "ಬಿರಿಯಾನಿ",
      "ಸುವಾಸನೆಯ ಉದ್ದ ಅಕ್ಕಿ ಮತ್ತು ಮಸಾಲೆಗಳಿಂದ ನಿಧಾನವಾಗಿ ಬೇಯಿಸಿದ ಬಿರಿಯಾನಿ."
    ],
    "ml": [
      "ബിരിയാണി",
      "സുഗന്ധമുള്ള നീളൻ അരിയും മസാലകളും ചേർത്ത് പതുക്കെ പാകം ചെയ്ത ബിരിയാണി."
    ],
    "pa": [
      "ਬਿਰਯਾਨੀ",
      "ਖੁਸ਼ਬੂਦਾਰ ਲੰਮੇ ਚੌਲ ਅਤੇ ਮਸਾਲਿਆਂ ਨਾਲ ਹੌਲੀ ਪਕਾਈ ਬਿਰਯਾਨੀ।"
    ],
    "or": [
      "ବିରିୟାନି",
      "ସୁଗନ୍ଧିତ ଲମ୍ବା ଚାଉଳ ଏବଂ ମସଲାରେ ଧୀରେ ରନ୍ଧା ବିରିୟାନି।"
    ],
    "as": [
      "বিৰিয়ানি",
      "সুগন্ধি দীঘল চাউল আৰু মচলাৰে লাহে লাহে ৰন্ধা বিৰিয়ানি।"
    ]
  },
  "butter roti": {
    "en": [
      "Butter Roti",
      "Soft whole-wheat roti served hot with melted butter."
    ],
    "hi": [
      "बटर रोटी",
      "मुलायम गेहूं की रोटी, गर्म और मक्खन के साथ परोसी जाती है।"
    ],
    "mr": [
      "बटर रोटी",
      "मऊ गव्हाची रोटी गरम आणि लोण्यासह दिली जाते."
    ],
    "ta": [
      "பட்டர் ரொட்டி",
      "மென்மையான கோதுமை ரொட்டி சூடாக வெண்ணெயுடன் பரிமாறப்படுகிறது."
    ],
    "te": [
      "బటర్ రోటీ",
      "మృదువైన గోధుమ రోటీని వేడిగా వెన్నతో అందిస్తారు."
    ],
    "bn": [
      "বাটার রুটি",
      "নরম গমের রুটি গরম ও মাখনসহ পরিবেশন করা হয়।"
    ],
    "gu": [
      "બટર રોટી",
      "નરમ ઘઉંની રોટી ગરમ અને માખણ સાથે પીરસાય છે."
    ],
    "kn": [
      "ಬಟರ್ ರೋಟಿ",
      "ಮೃದುವಾದ ಗೋಧಿ ರೋಟಿಯನ್ನು ಬಿಸಿ ಬೆಣ್ಣೆಯೊಂದಿಗೆ ನೀಡಲಾಗುತ್ತದೆ."
    ],
    "ml": [
      "ബട്ടർ റോട്ടി",
      "മൃദുവായ ഗോതമ്പ് റോട്ടി ചൂടോടെ വെണ്ണയോടെ നൽകുന്നു."
    ],
    "pa": [
      "ਬਟਰ ਰੋਟੀ",
      "ਨਰਮ ਕਣਕ ਦੀ ਰੋਟੀ ਗਰਮ ਮੱਖਣ ਨਾਲ ਪਰੋਸੀ ਜਾਂਦੀ ਹੈ।"
    ],
    "or": [
      "ବଟର ରୋଟି",
      "ନରମ ଗହମ ରୋଟି ଗରମ ଏବଂ ମଖନ ସହ ପରିବେଶିତ।"
    ],
    "as": [
      "বাটাৰ ৰুটি",
      "কোমল ঘেঁহুৰ ৰুটি গৰম মাখনৰ সৈতে পৰিৱেশন কৰা হয়।"
    ]
  },
  "coffee": {
    "en": [
      "Coffee",
      "Freshly brewed aromatic coffee with a smooth, rich finish."
    ],
    "hi": [
      "कॉफी",
      "ताज़ा बनी सुगंधित कॉफी, मुलायम और भरपूर स्वाद के साथ।"
    ],
    "mr": [
      "कॉफी",
      "ताजी बनवलेली सुगंधी कॉफी, मऊ आणि समृद्ध चवीची."
    ],
    "ta": [
      "காபி",
      "புதிதாக காய்ச்சிய மணமுள்ள காபி, மென்மையான செறிந்த சுவையுடன்."
    ],
    "te": [
      "కాఫీ",
      "తాజాగా తయారైన సువాసన కాఫీ, మృదువైన గాఢ రుచితో."
    ],
    "bn": [
      "কফি",
      "সদ্য তৈরি সুগন্ধি কফি, মসৃণ ও সমৃদ্ধ স্বাদে।"
    ],
    "gu": [
      "કોફી",
      "તાજી બનાવેલી સુગંધિત કોફી, નરમ અને સમૃદ્ધ સ્વાદ સાથે."
    ],
    "kn": [
      "ಕಾಫಿ",
      "ತಾಜಾಗಿ ತಯಾರಿಸಿದ ಸುಗಂಧ ಕಾಫಿ, ಮೃದುವಾದ ಗಾಢ ರುಚಿಯೊಂದಿಗೆ."
    ],
    "ml": [
      "കോഫി",
      "പുതുതായി തയ്യാറാക്കിയ സുഗന്ധമുള്ള കോഫി, മൃദുവായ സമൃദ്ധ രുചിയോടെ."
    ],
    "pa": [
      "ਕੌਫੀ",
      "ਤਾਜ਼ਾ ਬਣੀ ਸੁਗੰਧਿਤ ਕੌਫੀ, ਨਰਮ ਅਤੇ ਭਰਪੂਰ ਸਵਾਦ ਨਾਲ।"
    ],
    "or": [
      "କଫି",
      "ତାଜା ପ୍ରସ୍ତୁତ ସୁଗନ୍ଧିତ କଫି, ମୃଦୁ ଓ ଗାଢ଼ ସ୍ୱାଦରେ।"
    ],
    "as": [
      "কফি",
      "সতেজভাৱে বনোৱা সুগন্ধি কফি, মিহি আৰু সমৃদ্ধ সোৱাদেৰে।"
    ]
  },
  "dal tadka": {
    "en": [
      "Dal Tadka",
      "Yellow lentils tempered with cumin, garlic and aromatic spices."
    ],
    "hi": [
      "दाल तड़का",
      "जीरा, लहसुन और सुगंधित मसालों के तड़के वाली पीली दाल।"
    ],
    "mr": [
      "डाळ तडका",
      "जिरे, लसूण आणि सुगंधी मसाल्यांची फोडणी दिलेली पिवळी डाळ."
    ],
    "ta": [
      "தால் தட்கா",
      "சீரகம், பூண்டு மற்றும் மணமுள்ள மசாலாவுடன் தாளித்த மஞ்சள் பருப்பு."
    ],
    "te": [
      "దాల్ తడ్కా",
      "జీలకర్ర, వెల్లుల్లి మరియు సువాసన మసాలాలతో తాలింపు చేసిన పప్పు."
    ],
    "bn": [
      "ডাল তড়কা",
      "জিরা, রসুন ও সুগন্ধি মসলার ফোড়ন দেওয়া হলুদ ডাল।"
    ],
    "gu": [
      "દાળ તડકા",
      "જીરું, લસણ અને સુગંધિત મસાલાના વઘારવાળી પીળી દાળ."
    ],
    "kn": [
      "ದಾಲ್ ತಡ್ಕಾ",
      "ಜೀರಿಗೆ, ಬೆಳ್ಳುಳ್ಳಿ ಮತ್ತು ಸುಗಂಧ ಮಸಾಲೆಯ ಒಗ್ಗರಣೆ ಹಾಕಿದ ಬೇಳೆ."
    ],
    "ml": [
      "ദാൽ തട്ക",
      "ജീരകം, വെളുത്തുള്ളി, സുഗന്ധ മസാലകൾ ചേർത്ത് താളിച്ച മഞ്ഞ പരിപ്പ്."
    ],
    "pa": [
      "ਦਾਲ ਤੜਕਾ",
      "ਜੀਰਾ, ਲਸਣ ਅਤੇ ਸੁਗੰਧਿਤ ਮਸਾਲਿਆਂ ਦੇ ਤੜਕੇ ਵਾਲੀ ਪੀਲੀ ਦਾਲ।"
    ],
    "or": [
      "ଡାଲ ତଡକା",
      "ଜିରା, ରସୁଣ ଏବଂ ସୁଗନ୍ଧିତ ମସଲାର ଛୁଙ୍କ ସହ ହଳଦିଆ ଡାଲ।"
    ],
    "as": [
      "দাইল তড়কা",
      "জিৰা, নহৰু আৰু সুগন্ধি মচলাৰ ফোৰণ দিয়া হালধীয়া দাইল।"
    ]
  },
  "paneer butter masala": {
    "en": [
      "Paneer Butter Masala",
      "Tender paneer cubes in a rich, creamy tomato and butter gravy."
    ],
    "hi": [
      "पनीर बटर मसाला",
      "मलाईदार टमाटर और मक्खन की ग्रेवी में नरम पनीर के टुकड़े।"
    ],
    "mr": [
      "पनीर बटर मसाला",
      "मलाईदार टोमॅटो आणि लोण्याच्या ग्रेव्हीत मऊ पनीरचे तुकडे."
    ],
    "ta": [
      "பனீர் பட்டர் மசாலா",
      "கிரீமியான தக்காளி மற்றும் வெண்ணெய் கிரேவியில் மென்மையான பனீர் துண்டுகள்."
    ],
    "te": [
      "పనీర్ బటర్ మసాలా",
      "క్రీమీ టమాటా-వెన్న గ్రేవీలో మృదువైన పనీర్ ముక్కలు."
    ],
    "bn": [
      "পনির বাটার মাসালা",
      "ক্রিমি টমেটো ও মাখনের গ্রেভিতে নরম পনিরের টুকরো।"
    ],
    "gu": [
      "પનીર બટર મસાલા",
      "ક્રીમી ટમેટા અને માખણની ગ્રેવીમાં નરમ પનીરના ટુકડા."
    ],
    "kn": [
      "ಪನೀರ್ ಬಟರ್ ಮಸಾಲಾ",
      "ಕ್ರೀಮಿ ಟೊಮೇಟೊ-ಬೆಣ್ಣೆ ಗ್ರೇವಿಯಲ್ಲಿ ಮೃದುವಾದ ಪನೀರ್ ತುಂಡುಗಳು."
    ],
    "ml": [
      "പനീർ ബട്ടർ മസാല",
      "ക്രീമിയായ തക്കാളി-വെണ്ണ ഗ്രേവിയിൽ മൃദുവായ പനീർ കഷണങ്ങൾ."
    ],
    "pa": [
      "ਪਨੀਰ ਬਟਰ ਮਸਾਲਾ",
      "ਕ੍ਰੀਮੀ ਟਮਾਟਰ ਅਤੇ ਮੱਖਣ ਦੀ ਗਰੇਵੀ ਵਿੱਚ ਨਰਮ ਪਨੀਰ।"
    ],
    "or": [
      "ପନିର ବଟର ମସଲା",
      "କ୍ରିମି ଟମାଟୋ ଓ ମଖନ ଗ୍ରେଭିରେ ନରମ ପନିର ଖଣ୍ଡ।"
    ],
    "as": [
      "পনীৰ বাটাৰ মচলা",
      "ক্ৰীমি টমেটো আৰু মাখনৰ গ্ৰেভিত কোমল পনীৰৰ টুকুৰা।"
    ]
  },
  "poha": {
    "en": [
      "Poha",
      "Light flattened rice cooked with herbs, vegetables and gentle spices."
    ],
    "hi": [
      "पोहा",
      "जड़ी-बूटियों, सब्जियों और हल्के मसालों के साथ बनाया गया हल्का पोहा।"
    ],
    "mr": [
      "पोहे",
      "हिरवी पाने, भाज्या आणि सौम्य मसाल्यांसह तयार केलेले हलके पोहे."
    ],
    "ta": [
      "அவல் உப்புமா",
      "மூலிகைகள், காய்கறிகள் மற்றும் மென்மையான மசாலாவுடன் சமைத்த அவல்."
    ],
    "te": [
      "అటుకుల ఉప్మా",
      "ఆకుకూరలు, కూరగాయలు మరియు మృదువైన మసాలాలతో చేసిన అటుకులు."
    ],
    "bn": [
      "পোহা",
      "হার্বস, সবজি ও হালকা মসলায় রান্না করা চিঁড়া।"
    ],
    "gu": [
      "પોહા",
      "હર્બ્સ, શાકભાજી અને હળવા મસાલા સાથે બનાવેલા પોહા."
    ],
    "kn": [
      "ಅವಲಕ್ಕಿ",
      "ಸೊಪ್ಪು, ತರಕಾರಿ ಮತ್ತು ಸೌಮ್ಯ ಮಸಾಲೆಗಳೊಂದಿಗೆ ಮಾಡಿದ ಅವಲಕ್ಕಿ."
    ],
    "ml": [
      "അവൽ ഉപ്പുമാവ്",
      "പച്ചിലകൾ, പച്ചക്കറികൾ, മൃദുവായ മസാലകൾ ചേർത്ത് തയ്യാറാക്കിയ അവൽ."
    ],
    "pa": [
      "ਪੋਹਾ",
      "ਹਰੀਆਂ ਜੜੀਆਂ, ਸਬਜ਼ੀਆਂ ਅਤੇ ਹਲਕੇ ਮਸਾਲਿਆਂ ਨਾਲ ਬਣਿਆ ਪੋਹਾ।"
    ],
    "or": [
      "ପୋହା",
      "ଶାଗ, ସବ୍ଜି ଓ ହାଲୁକା ମସଲାରେ ପ୍ରସ୍ତୁତ ଚୁଡା।"
    ],
    "as": [
      "পোহা",
      "শাকপাত, পাচলি আৰু মৃদু মচলাৰে ৰন্ধা চিৰা।"
    ]
  },
  "tea": {
    "en": [
      "Tea",
      "A soothing aromatic cup of tea brewed with traditional Indian spices."
    ],
    "hi": [
      "चाय",
      "पारंपरिक भारतीय मसालों के साथ बनी सुगंधित और सुकून देने वाली चाय।"
    ],
    "mr": [
      "चहा",
      "पारंपरिक भारतीय मसाल्यांसह बनवलेला सुगंधी आणि ताजेतवाना चहा."
    ],
    "ta": [
      "தேநீர்",
      "பாரம்பரிய இந்திய மசாலாவுடன் தயாரித்த மணமுள்ள தேநீர்."
    ],
    "te": [
      "టీ",
      "సాంప్రదాయ భారతీయ మసాలాలతో తయారైన సువాసన టీ."
    ],
    "bn": [
      "চা",
      "ঐতিহ্যবাহী ভারতীয় মসলায় তৈরি সুগন্ধি আরামদায়ক চা।"
    ],
    "gu": [
      "ચા",
      "પરંપરાગત ભારતીય મસાલા સાથે બનાવેલી સુગંધિત ચા."
    ],
    "kn": [
      "ಚಹಾ",
      "ಸಾಂಪ್ರದಾಯಿಕ ಭಾರತೀಯ ಮಸಾಲೆಗಳೊಂದಿಗೆ ತಯಾರಿಸಿದ ಸುಗಂಧ ಚಹಾ."
    ],
    "ml": [
      "ചായ",
      "പരമ്പരാഗത ഇന്ത്യൻ മസാലകളോടെ തയ്യാറാക്കിയ സുഗന്ധമുള്ള ചായ."
    ],
    "pa": [
      "ਚਾਹ",
      "ਰਵਾਇਤੀ ਭਾਰਤੀ ਮਸਾਲਿਆਂ ਨਾਲ ਬਣੀ ਸੁਗੰਧਿਤ ਚਾਹ।"
    ],
    "or": [
      "ଚା",
      "ପାରମ୍ପରିକ ଭାରତୀୟ ମସଲାରେ ପ୍ରସ୍ତୁତ ସୁଗନ୍ଧିତ ଚା।"
    ],
    "as": [
      "চাহ",
      "পৰম্পৰাগত ভাৰতীয় মচলাৰে বনোৱা সুগন্ধি চাহ।"
    ]
  },
  "upma": {
    "en": [
      "Upma",
      "Warm semolina cooked with vegetables, mustard seeds and cashews."
    ],
    "hi": [
      "उपमा",
      "सब्जियों, राई और काजू के साथ बना गर्म सूजी उपमा।"
    ],
    "mr": [
      "उपमा",
      "भाज्या, मोहरी आणि काजूसह बनवलेला गरम रव्याचा उपमा."
    ],
    "ta": [
      "உப்புமா",
      "காய்கறிகள், கடுகு மற்றும் முந்திரியுடன் சமைத்த ரவை உப்புமா."
    ],
    "te": [
      "ఉప్మా",
      "కూరగాయలు, ఆవాలు మరియు జీడిపప్పుతో చేసిన రవ్వ ఉప్మా."
    ],
    "bn": [
      "উপমা",
      "সবজি, সরিষা ও কাজু দিয়ে রান্না করা সুজি উপমা।"
    ],
    "gu": [
      "ઉપમા",
      "શાકભાજી, રાઈ અને કાજુ સાથે બનાવેલો રવાનો ઉપમા."
    ],
    "kn": [
      "ಉಪ್ಪಿಟ್ಟು",
      "ತರಕಾರಿ, ಸಾಸಿವೆ ಮತ್ತು ಗೋಡಂಬಿಯೊಂದಿಗೆ ಮಾಡಿದ ರವೆ ಉಪ್ಪಿಟ್ಟು."
    ],
    "ml": [
      "ഉപ്പുമാവ്",
      "പച്ചക്കറികൾ, കടുക്, കശുവണ്ടി ചേർത്ത് തയ്യാറാക്കിയ റവ ഉപ്പുമാവ്."
    ],
    "pa": [
      "ਉਪਮਾ",
      "ਸਬਜ਼ੀਆਂ, ਸਰੋਂ ਅਤੇ ਕਾਜੂ ਨਾਲ ਬਣਿਆ ਗਰਮ ਸੂਜੀ ਉਪਮਾ।"
    ],
    "or": [
      "ଉପମା",
      "ସବ୍ଜି, ସୋରିଷ ଏବଂ କାଜୁ ସହ ପ୍ରସ୍ତୁତ ସୁଜି ଉପମା।"
    ],
    "as": [
      "উপমা",
      "পাচলি, সৰিয়হ আৰু কাজুৰে বনোৱা গৰম ছুজিৰ উপমা।"
    ]
  },
  "veg sandwich": {
    "en": [
      "Veg Sandwich",
      "Grilled sandwich layered with crisp vegetables and flavourful chutney."
    ],
    "hi": [
      "वेज सैंडविच",
      "कुरकुरी सब्जियों और स्वादिष्ट चटनी से भरा ग्रिल्ड सैंडविच।"
    ],
    "mr": [
      "व्हेज सँडविच",
      "कुरकुरी भाज्या आणि चवदार चटणीचे थर असलेले ग्रिल्ड सँडविच."
    ],
    "ta": [
      "வெஜ் சாண்ட்விச்",
      "மொறுமொறு காய்கறிகள் மற்றும் சுவையான சட்னியுடன் கிரில் செய்த சாண்ட்விச்."
    ],
    "te": [
      "వెజ్ సాండ్‌విచ్",
      "కరకరలాడే కూరగాయలు మరియు రుచికరమైన చట్నీతో గ్రిల్ చేసిన సాండ్‌విచ్."
    ],
    "bn": [
      "ভেজ স্যান্ডউইচ",
      "মচমচে সবজি ও সুস্বাদু চাটনি দিয়ে গ্রিল করা স্যান্ডউইচ।"
    ],
    "gu": [
      "વેજ સેન્ડવિચ",
      "કરકરી શાકભાજી અને સ્વાદિષ્ટ ચટણી સાથે ગ્રિલ્ડ સેન્ડવિચ."
    ],
    "kn": [
      "ವೆಜ್ ಸ್ಯಾಂಡ್‌ವಿಚ್",
      "ಕುರುಕು ತರಕಾರಿ ಮತ್ತು ರುಚಿಕರ ಚಟ್ನಿಯೊಂದಿಗೆ ಗ್ರಿಲ್ ಮಾಡಿದ ಸ್ಯಾಂಡ್‌ವಿಚ್."
    ],
    "ml": [
      "വെജ് സാൻഡ്വിച്ച്",
      "ക്രിസ്പ് പച്ചക്കറികളും രുചികരമായ ചട്നിയും ചേർത്ത ഗ്രിൽഡ് സാൻഡ്വിച്ച്."
    ],
    "pa": [
      "ਵੈਜ ਸੈਂਡਵਿਚ",
      "ਕਰਕਰੀਆਂ ਸਬਜ਼ੀਆਂ ਅਤੇ ਸੁਆਦੀ ਚਟਨੀ ਨਾਲ ਗ੍ਰਿੱਲਡ ਸੈਂਡਵਿਚ।"
    ],
    "or": [
      "ଭେଜ୍ ସାଣ୍ଡୱିଚ୍",
      "କରକରା ସବ୍ଜି ଓ ସ୍ୱାଦିଷ୍ଟ ଚଟଣି ସହ ଗ୍ରିଲ୍ ସାଣ୍ଡୱିଚ୍।"
    ],
    "as": [
      "ভেজ ছেণ্ডউইচ",
      "কৰকৰীয়া পাচলি আৰু সোৱাদযুক্ত চাটনিৰে গ্ৰিল কৰা ছেণ্ডউইচ।"
    ]
  },
  "veg thali": {
    "en": [
      "Veg Thali",
      "A complete vegetarian meal with curries, dal, rice, roti, salad and dessert."
    ],
    "hi": [
      "वेज थाली",
      "सब्जी, दाल, चावल, रोटी, सलाद और मिठाई के साथ संपूर्ण शाकाहारी भोजन।"
    ],
    "mr": [
      "व्हेज थाळी",
      "भाजी, डाळ, भात, पोळी, कोशिंबीर आणि गोड पदार्थासह पूर्ण शाकाहारी जेवण."
    ],
    "ta": [
      "வெஜ் தாளி",
      "கறி, பருப்பு, சாதம், ரொட்டி, சாலட் மற்றும் இனிப்புடன் முழு சைவ உணவு."
    ],
    "te": [
      "వెజ్ థాలి",
      "కూరలు, పప్పు, అన్నం, రోటీ, సలాడ్ మరియు స్వీట్‌తో సంపూర్ణ శాకాహార భోజనం."
    ],
    "bn": [
      "ভেজ থালি",
      "তরকারি, ডাল, ভাত, রুটি, সালাদ ও মিষ্টিসহ সম্পূর্ণ নিরামিষ খাবার।"
    ],
    "gu": [
      "વેજ થાળી",
      "શાક, દાળ, ભાત, રોટલી, સલાડ અને મીઠાઈ સાથે સંપૂર્ણ શાકાહારી ભોજન."
    ],
    "kn": [
      "ವೆಜ್ ಥಾಳಿ",
      "ಪಲ್ಯ, ಬೇಳೆ, ಅನ್ನ, ರೋಟಿ, ಸಲಾಡ್ ಮತ್ತು ಸಿಹಿಯೊಂದಿಗೆ ಸಂಪೂರ್ಣ ಸಸ್ಯಾಹಾರಿ ಊಟ."
    ],
    "ml": [
      "വെജ് താലി",
      "കറികൾ, പരിപ്പ്, ചോറ്, റോട്ടി, സലാഡ്, മധുരം ഉൾപ്പെട്ട സമ്പൂർണ്ണ സസ്യാഹാര ഭക്ഷണം."
    ],
    "pa": [
      "ਵੈਜ ਥਾਲੀ",
      "ਸਬਜ਼ੀ, ਦਾਲ, ਚਾਵਲ, ਰੋਟੀ, ਸਲਾਦ ਅਤੇ ਮਿਠਾਈ ਨਾਲ ਪੂਰਾ ਸ਼ਾਕਾਹਾਰੀ ਭੋਜਨ।"
    ],
    "or": [
      "ଭେଜ୍ ଥାଳି",
      "ତରକାରୀ, ଡାଲ, ଭାତ, ରୋଟି, ସାଲାଡ୍ ଓ ମିଠା ସହ ସମ୍ପୂର୍ଣ୍ଣ ଶାକାହାରୀ ଭୋଜନ।"
    ],
    "as": [
      "ভেজ থালি",
      "তৰকাৰী, দাইল, ভাত, ৰুটি, চালাড আৰু মিঠাইসহ সম্পূৰ্ণ নিৰামিষ আহাৰ।"
    ]
  }
}

const MODIFIER_TRANSLATIONS = {
  "add-ons": {
    "en": "Add-ons",
    "hi": "ऐड-ऑन",
    "mr": "अॅड-ऑन्स",
    "ta": "கூடுதல்",
    "te": "అడ్-ఆన్స్",
    "bn": "অ্যাড-অন",
    "gu": "એડ-ઓન",
    "kn": "ಆಡ್-ಆನ್‌ಗಳು",
    "ml": "ആഡ്-ഓൺസ്",
    "pa": "ਐਡ-ਆਨ",
    "or": "ଆଡ୍-ଅନ୍",
    "as": "এড-অন"
  },
  "extra cheese": {
    "en": "Extra Cheese",
    "hi": "अतिरिक्त चीज़",
    "mr": "अतिरिक्त चीज",
    "ta": "கூடுதல் சீஸ்",
    "te": "అదనపు చీజ్",
    "bn": "অতিরিক্ত চিজ",
    "gu": "વધારાનું ચીઝ",
    "kn": "ಹೆಚ್ಚುವರಿ ಚೀಸ್",
    "ml": "അധിക ചീസ്",
    "pa": "ਵਾਧੂ ਚੀਜ਼",
    "or": "ଅତିରିକ୍ତ ଚିଜ୍",
    "as": "অতিৰিক্ত চীজ"
  },
  "french fries": {
    "en": "French Fries",
    "hi": "फ्रेंच फ्राइज़",
    "mr": "फ्रेंच फ्राइज",
    "ta": "பிரெஞ்ச் ஃப்ரைஸ்",
    "te": "ఫ్రెంచ్ ఫ్రైస్",
    "bn": "ফ্রেঞ্চ ফ্রাই",
    "gu": "ફ્રેન્ચ ફ્રાઇઝ",
    "kn": "ಫ್ರೆಂಚ್ ಫ್ರೈಸ್",
    "ml": "ഫ്രഞ്ച് ഫ്രൈസ്",
    "pa": "ਫ੍ਰੈਂਚ ਫ੍ਰਾਈਜ਼",
    "or": "ଫ୍ରେଞ୍ଚ ଫ୍ରାଇଜ୍",
    "as": "ফ্ৰেঞ্চ ফ্ৰাইজ"
  }
}


export const DINING_LOCALES = [
  'en', 'hi', 'mr', 'ta', 'te', 'bn',
  'gu', 'kn', 'ml', 'pa', 'or', 'as',
]

function interpolate(value, variables = {}) {
  return String(value || '').replace(/\{([a-zA-Z0-9_]+)\}/g, (_, key) => (
    Object.prototype.hasOwnProperty.call(variables, key) ? String(variables[key]) : `{${key}}`
  ))
}

export function getDiningCopy(locale = 'en') {
  const code = DINING_LOCALES.includes(locale) ? locale : 'en'
  const guide = getGuideCopy(code)
  const values = { ...EN, ...(OVERRIDES[code] || {}) }
  return {
    ...values,
    room: values.room || guide.room,
    guestGuide: values.guestGuide || guide.digitalGuide,
    inRoomServices: values.inRoomServices || guide.services,
    interpolate: (key, variables) => interpolate(values[key] || EN[key] || key, variables),
  }
}

function cleanKey(value) {
  return String(value || '')
    .trim()
    .toLocaleLowerCase('en')
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function directTranslation(translations, locale) {
  if (!translations || typeof translations !== 'object') return {}
  const value = translations[locale]
  return value && typeof value === 'object' ? value : {}
}

export function getCommonCategoryTranslation(value, locale = 'en') {
  const code = DINING_LOCALES.includes(locale) ? locale : 'en'
  const key = cleanKey(value).replaceAll(' ', '')
  const aliases = {
    beverage: 'beverages', beverages: 'beverages', breakfast: 'breakfast',
    lunch: 'lunch', dinner: 'dinner', meal: 'meal', meals: 'meal', all: 'all',
  }
  return CATEGORY_TRANSLATIONS[code]?.[aliases[key] || key] || String(value || '')
}

export function localizeMenuItem(item, locale = 'en', defaultLocale = 'en') {
  const direct = directTranslation(item?.translations, locale)
  const fallback = directTranslation(item?.translations, defaultLocale)
  const common = ITEM_TRANSLATIONS[cleanKey(item?.item_name)]?.[locale]
  const categoryDirect = directTranslation(item?.category_translations, locale)
  const categoryFallback = directTranslation(item?.category_translations, defaultLocale)
  const localizedGroups = (item?.modifier_groups || []).map((group) => localizeModifierGroup(group, locale, defaultLocale))
  return {
    ...item,
    item_name: direct.item_name || fallback.item_name || common?.[0] || item?.item_name || '',
    description: direct.description || fallback.description || common?.[1] || item?.description || '',
    category: categoryDirect.name || categoryFallback.name || getCommonCategoryTranslation(item?.category, locale),
    modifier_groups: localizedGroups,
  }
}

export function localizeModifierGroup(group, locale = 'en', defaultLocale = 'en') {
  const direct = directTranslation(group?.translations, locale)
  const fallback = directTranslation(group?.translations, defaultLocale)
  const commonName = MODIFIER_TRANSLATIONS[cleanKey(group?.name)]?.[locale]
  return {
    ...group,
    name: direct.name || fallback.name || commonName || group?.name || '',
    modifiers: (group?.modifiers || []).map((modifier) => localizeModifier(modifier, locale, defaultLocale)),
  }
}

export function localizeModifier(modifier, locale = 'en', defaultLocale = 'en') {
  const direct = directTranslation(modifier?.translations, locale)
  const fallback = directTranslation(modifier?.translations, defaultLocale)
  const commonName = MODIFIER_TRANSLATIONS[cleanKey(modifier?.name)]?.[locale]
  return {
    ...modifier,
    name: direct.name || fallback.name || commonName || modifier?.name || '',
  }
}

export function localizeOrderItem(item, locale = 'en', defaultLocale = 'en') {
  const direct = directTranslation(item?.translations, locale)
  const fallback = directTranslation(item?.translations, defaultLocale)
  const common = ITEM_TRANSLATIONS[cleanKey(item?.item_name)]?.[locale]
  return {
    ...item,
    item_name: direct.item_name || fallback.item_name || common?.[0] || item?.item_name || '',
    modifiers: (item?.modifiers || []).map((modifier) => localizeModifier(modifier, locale, defaultLocale)),
  }
}

export function getTranslationSeed(entity, locale, type = 'item') {
  const code = DINING_LOCALES.includes(locale) ? locale : 'en'
  const direct = directTranslation(entity?.translations, code)
  if (type === 'category') {
    return { name: direct.name || getCommonCategoryTranslation(entity?.name, code) || entity?.name || '' }
  }
  if (type === 'group' || type === 'modifier') {
    return { name: direct.name || MODIFIER_TRANSLATIONS[cleanKey(entity?.name)]?.[code] || entity?.name || '' }
  }
  const common = ITEM_TRANSLATIONS[cleanKey(entity?.item_name)]?.[code]
  return {
    item_name: direct.item_name || common?.[0] || entity?.item_name || '',
    description: direct.description || common?.[1] || entity?.description || '',
  }
}

export function localizeStatus(status, copy) {
  const map = {
    pending: copy.statusPending,
    accepted: copy.statusAccepted,
    preparing: copy.statusPreparing,
    ready: copy.statusReady,
    out_for_delivery: copy.statusOutForDelivery,
    delivered: copy.statusDelivered,
    cancelled: copy.statusCancelled,
  }
  return map[status] || String(status || '').replaceAll('_', ' ')
}

export function getLocalizedNotification(notification, copy) {
  const event = String(notification?.event_key || '')
  const titles = {
    accepted: copy.statusAccepted,
    preparing: copy.statusPreparing,
    ready: copy.statusReady,
    out_for_delivery: copy.statusOutForDelivery,
    delivered: copy.statusDelivered,
    cancelled: copy.statusCancelled,
  }
  return {
    ...notification,
    title: titles[event] || notification?.title || copy.latestUpdates,
    message: notification?.message || copy.liveTrackingBody,
  }
}
