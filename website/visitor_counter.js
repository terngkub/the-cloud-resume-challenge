const url = 'https://resume.nattapol.com/api/increase-visitor-counter'
const options = {method: 'POST'}

async function increaseAndGetVisitorCounter() {
    let response = await fetch(url, options)
    let responseJson = await response.json()
    return responseJson['visitor-counter']
}

async function showVisitorCounter() {
    let visitor_counter = await increaseAndGetVisitorCounter()
    document.getElementById("visitor-counter-value").innerHTML = visitor_counter
    console.log(visitor_counter)
}

showVisitorCounter()