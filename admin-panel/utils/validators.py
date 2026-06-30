import re

def validate_cnpj(cnpj: str) -> bool:
    # Remove non-digits
    cnpj = re.sub(r'\D', '', cnpj)
    
    if len(cnpj) != 14:
        return False
        
    # Block list of invalid repeating CNPJs
    if cnpj in [str(i) * 14 for i in range(10)]:
        return False
        
    # Validation digit calculations
    def calculate_digit(numbers, weights):
        total = sum(int(num) * weight for num, weight in zip(numbers, weights))
        remainder = total % 11
        return 0 if remainder < 2 else 11 - remainder

    weights_1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    weights_2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
    
    digit_1 = calculate_digit(cnpj[:12], weights_1)
    digit_2 = calculate_digit(cnpj[:13], weights_2)
    
    return int(cnpj[12]) == digit_1 and int(cnpj[13]) == digit_2

def validate_email(email: str) -> bool:
    email_regex = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
    return bool(email_regex.match(email))

def validate_url(url: str) -> bool:
    url_regex = re.compile(
        r'^https?://' # http:// or https://
        r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|' # domain...
        r'localhost|' # localhost...
        r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})' # ...or ip
        r'(?::\d+)?' # optional port
        r'(?:/?|[/?]\S+)$', re.IGNORECASE)
    return bool(url_regex.match(url))
